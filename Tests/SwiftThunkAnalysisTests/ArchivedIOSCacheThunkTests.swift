import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import SwiftThunkAnalysis
import SwiftDump

/// Where the archived-device-cache-gated suite below finds its cache. A
/// separate type on purpose: a `@Suite(.enabled(if:))` condition that reads
/// a static of the suite it decorates is a circular macro reference.
enum ArchivedIOSCacheFixtures {
    /// iOS 26.3.1, arm64e: a device cache, whose cross-image calls go
    /// through stub islands rather than GOT-loading stubs.
    static let cachePath = "/Volumes/DyldSharedCaches/iOS/26.3.1/dyld_shared_cache_arm64e"
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath) }
}

/// SwiftUI and SwiftUICore as an iOS device cache ships them. Measured
/// 2026-09-13 before islands were recognized: 7 and 2 unread references,
/// no branch comment at all — every cross-image call was a `bl` to an
/// `adrp` / `add` / `br` trampoline between the images, which the
/// environment took for nothing it knew.
@Suite(.serialized, .enabled(if: ArchivedIOSCacheFixtures.hasCache))
struct ArchivedIOSCacheThunkTests {
    private func image(named name: String) throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: ArchivedIOSCacheFixtures.cachePath))
        return try #require(cache.machOFile(by: .name(name)), "the archived cache has no \(name)")
    }

    private func resolvedFieldTexts(ofTypeNamed typeName: String, in machOFile: MachOFile) throws -> [String: String] {
        var texts: [String: String] = [:]
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let name = try? SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default),
                  name == typeName,
                  let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile)
            else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile),
                      typeNode.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                texts[try record.fieldName(in: machOFile)] = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout).print(using: .default)
            }
        }
        return texts
    }

    @Test func theNoncopyableFieldsResolveThroughStubIslands() throws {
        let swiftUI = try image(named: "SwiftUI")
        let schedulerFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.BGTaskSchedulerWrapper", in: swiftUI)
        #expect(schedulerFields["observedTasks"] == "Synchronization.Mutex<Swift.Set<Swift.String>>")
        let lazyItemFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.Drag.LazyItem", in: swiftUI)
        #expect(lazyItemFields["state"] == "Synchronization.Mutex<SwiftUI.Drag.LazyItem<A>.State>")

        // The iOS build spells the private nested types without a
        // discriminator (`…Definition.Storage`), the macOS build with one
        // (`…Definition.(Storage in _DD01…)`); only the type itself is pinned.
        let swiftUICore = try image(named: "SwiftUICore")
        let settingsFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.PlatformAccessibilitySettingsDefinition", in: swiftUICore)
        #expect(settingsFields["cache"]?.hasPrefix("Synchronization.Mutex<SwiftUI.PlatformAccessibilitySettingsDefinition.") == true, "\(String(describing: settingsFields["cache"]))")
        #expect(settingsFields["cache"]?.contains("Storage") == true)
        let imageCacheFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.NamedImage.Cache", in: swiftUICore)
        #expect(imageCacheFields["data"]?.hasPrefix("Synchronization.Mutex<SwiftUI.NamedImage.Cache.") == true, "\(String(describing: imageCacheFields["data"]))")
        #expect(imageCacheFields["data"]?.contains("Data") == true)
    }

    @Test func everyConditionalWitnessResolvesThroughStubIslands() async throws {
        let swiftUI = try image(named: "SwiftUI")
        var unread: [String] = []
        var conditionalWitnessCount = 0
        for associatedType in try swiftUI.swift.associatedTypes {
            for record in associatedType.records {
                guard let mangledName = try? record.substitutedTypeName(in: swiftUI),
                      let node = try? SymbolicDemangler.demangleType(for: mangledName, in: swiftUI),
                      node.contains(Node.Kind.opaqueType)
                else { continue }
                let resolution = node.resolveOpaqueTypeCollectingConditionalCandidates(in: swiftUI)
                let text = await resolution.node.print(using: DemangleOptions.default)
                if text.contains("accessor function at") { unread.append(text) }
                if resolution.conditionalCandidates.count >= 2 { conditionalWitnessCount += 1 }
            }
        }
        #expect(unread.isEmpty, "still unread:\n\(unread.joined(separator: "\n"))")
        #expect(conditionalWitnessCount > 0, "the iOS 26.3.1 SwiftUI is expected to carry availability-conditional witnesses")
    }
}
