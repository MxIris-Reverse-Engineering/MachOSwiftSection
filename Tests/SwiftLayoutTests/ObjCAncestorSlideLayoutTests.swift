import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A statically-emitted Swift subclass of an ObjC class does **not** start its
/// fields at the ancestor's raw instance size: the compiler lays the ivars
/// from its own `class_ro_t.instanceStart`, and the ObjC runtime slides them
/// en masse when the actual superclass outgrows it (objc4 `moveIvars`, slide
/// rounded up to the class's maximum own-ivar alignment). A dyld-cache image
/// carries the pre-slid final `instanceStart`. The engine reads that own
/// `instanceStart` and reproduces the slide — previously it started at the
/// raw superclass size, misplacing every field of e.g. SwiftUI's
/// `AppKitTableHeaderCell` (`NSTableHeaderCell` is 241 bytes; the realized
/// field block starts at the slid 248, not 241). Found by the
/// SwiftUI/SwiftUICore/SwiftData whole-framework survey vs the live runtime.
@Suite
final class ObjCAncestorSlideLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// The own-`instanceStart` index covers the fixture's statically-emitted
    /// classes, and the no-drift case (compile-time == actual ancestor size)
    /// stays byte-identical: `ObjCMembersTest` over `NSObject` starts at 8,
    /// so the slide is zero and `StaticLayoutVsRuntimeTests` keeps pinning
    /// the unchanged offsets.
    @MainActor
    @Test func fixtureClassInstanceStartsIndexed() async throws {
        let index = ObjCClassIndex.swiftClassInstanceStartsByQualifiedName(in: machOImage)
        #expect(index["SymbolTestsCore.Classes.ObjCMembersTest"] == 8)
    }

    /// Real-drift end-to-end against the OS: SwiftUI classes over AppKit
    /// ancestors whose actual instance size is not word-aligned
    /// (`NSTableHeaderCell` = 241) or whose Swift superclass ends unaligned
    /// (`SplitViewChildController`'s chain, 116 → slid 120). The offline
    /// engine (dyld-cache `MachOFile` + dependency closure) must match the
    /// realized runtime ivar offsets exactly. Pinned to SwiftUI internals by
    /// name suffix — if a future OS removes both classes the
    /// `verifiedFieldCount` floor fails loudly and the targets need updating.
    @MainActor
    @Test func dyldCacheObjCAncestorClassesMatchRealizedIvars() async throws {
        let targetNameSuffixes = ["AppKitTableHeaderCell", "SplitViewChildController"]
        let swiftUIPath = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
        guard
            dlopen(swiftUIPath, RTLD_NOW) != nil,
            let runtimeImage = MachOImage(name: "SwiftUI"),
            let hostCache = FullDyldCache.host,
            let rootFile = hostCache.machOFiles().first(where: { $0.imagePath.hasSuffix("/SwiftUI") })
        else {
            Issue.record("SwiftUI could not be loaded from the host dyld cache")
            return
        }

        let universe = try ImageUniverse.dependencyClosure(root: rootFile)
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        var verifiedFieldCount = 0
        for contextDescriptor in try rootFile.swift.contextDescriptors {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                descriptor.isClass,
                !descriptor.typeContextDescriptor.layout.flags.isGeneric,
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: rootFile))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                targetNameSuffixes.contains(where: { qualifiedTypeName.contains($0) })
            else { continue }

            guard let realizedIvarOffsets = Self.realizedIvarOffsets(ofQualifiedTypeName: qualifiedTypeName, in: runtimeImage) else {
                Issue.record("no realized runtime class for \(qualifiedTypeName)")
                continue
            }

            let aggregate = try calculator.fieldLayout(of: descriptor)
            for field in aggregate.fields {
                guard case .computed = field.resolution else {
                    Issue.record("\(qualifiedTypeName).\(field.fieldName) degraded unexpectedly: \(field.resolution)")
                    continue
                }
                guard let runtimeOffset = realizedIvarOffsets[field.fieldName] else { continue }
                #expect(
                    field.offset == runtimeOffset,
                    "\(qualifiedTypeName).\(field.fieldName): static \(field.offset) != realized ivar \(runtimeOffset)"
                )
                verifiedFieldCount += 1
            }
        }
        #expect(verifiedFieldCount >= 3, "expected to verify several drifted-ancestor fields, got \(verifiedFieldCount)")
    }

    /// Field name → ivar offset of the **realized** ObjC class backing a Swift
    /// class in a loaded image — the authoritative runtime layout (the
    /// metadata accessor materializes the class, `class_getInstanceSize`
    /// forces realization, and `ivar_getOffset` reads the slid offsets).
    private static func realizedIvarOffsets(ofQualifiedTypeName qualifiedTypeName: String, in machO: MachOImage) -> [String: Int]? {
        for contextDescriptor in (try? machO.swift.contextDescriptors) ?? [] {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                descriptor.isClass,
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName,
                let accessor = try? descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO),
                let response = try? accessor(request: .init())
            else { continue }
            let anyClass = unsafeBitCast(UInt(response.value.address), to: AnyClass.self)
            _ = class_getInstanceSize(anyClass)
            var ivarCount: UInt32 = 0
            var offsets: [String: Int] = [:]
            if let ivars = class_copyIvarList(anyClass, &ivarCount) {
                defer { free(ivars) }
                for index in 0..<Int(ivarCount) {
                    guard let nameCString = ivar_getName(ivars[index]) else { continue }
                    offsets[String(cString: nameCString)] = ivar_getOffset(ivars[index])
                }
            }
            return offsets
        }
        return nil
    }
}
