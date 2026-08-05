import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A generic multi-payload enum whose layout is argument-independent is laid
/// out **statically with the spare-bits strategy** — the compiler bakes the
/// complete value-witness table into the generic metadata pattern and emits
/// `__swift5_builtin` (whole-type quintuple) + `__swift5_mpenum` (spare-bit
/// mask) records for the *unbound* type; the runtime's tagged
/// `swift_initEnumMetadataMultiPayload` never runs for any of its
/// instantiations. Only an argument-**dependent** generic multi-payload enum
/// (some payload's layout needs an argument) takes the runtime tagged path —
/// and such an enum gets **no** records, so record presence is the compiler's
/// own verdict, readable offline.
///
/// The engine previously modelled *every* generic multi-payload enum as
/// tagged, which mis-sized the `Swift.Dictionary.Iterator._Variant` family
/// (41/48/XI 254 instead of 40/40/XI 126) and every OS type embedding it —
/// found by the SwiftUI/SwiftUICore/SwiftData whole-framework survey against
/// the live runtime, and initially misattributed to metadata
/// prespecialization (a fresh instantiation with test-local argument types
/// reproduces the spare-bits layout, so it is pattern-baked, not
/// prespecialized).
@Suite
final class GenericSpareBitsEnumLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// The fixture mirror of the `Dictionary.Iterator._Variant` shape: payload
    /// words are native class references / fixed integers, so the layout is
    /// argument-independent with 7 common spare bits in word 0 → size 24,
    /// stride 24, XI 125 (128 minus 2 payload tags minus 1 empty-case tag).
    /// The tagged model would say 25 / 32 / XI 253 and push the holder's
    /// trailing field from 32 to 33.
    @MainActor
    @Test func spareBitsGenericEnumInstantiationMatchesRuntime() async throws {
        let holderName = "SymbolTestsCore.GenericFieldLayout.SpareBitsVariantEnumFieldHolder"
        guard let holderDescriptor = try fixtureTypeDescriptor(named: holderName) else { return }

        let calculator = try StaticLayoutCalculator(machO: machOImage)
        let staticLayout = try calculator.typeLayout(forDescriptor: holderDescriptor)
        #expect(staticLayout.size == 33, "Int(8) + spare-bits enum(24) + Int8 at 32, got size \(staticLayout.size)")
        #expect(staticLayout.stride == 40)
        #expect(staticLayout.extraInhabitantCount == 125, "the enum's spare-bits XI must propagate to the struct, got \(staticLayout.extraInhabitantCount)")

        let aggregate = try calculator.fieldLayout(of: holderDescriptor)
        #expect(
            aggregate.fields.map(\.offset) == [0, 8, 32],
            "trailing field must land at 32 (spare-bits enum is 24 bytes), got \(aggregate.fields.map(\.offset))"
        )

        // Ground truth: the live value-witness table of the holder.
        try expectRuntimeAgreement(staticLayout, for: holderDescriptor)

        // The offline MachOFile reader must agree with the in-process one.
        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        for contextDescriptor in try machOFile.swift.contextDescriptors {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                (try? MetadataReader.demangleContext(for: contextDescriptor, in: machOFile))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)) == holderName
            else { continue }
            let fileLayout = try fileCalculator.typeLayout(forDescriptor: descriptor)
            #expect(fileLayout.size == staticLayout.size)
            #expect(fileLayout.extraInhabitantCount == staticLayout.extraInhabitantCount)
            break
        }
    }

    /// The discriminating signal itself: the compiler emits a
    /// `__swift5_builtin` record (keyed by the generic-argument-free name) for
    /// the argument-independent generic multi-payload enum, and none for the
    /// argument-dependent one. If a future toolchain stops emitting these
    /// records the engine's detection breaks loudly here, not silently in
    /// layout results.
    @MainActor
    @Test func builtinRecordPresenceDiscriminatesFixedFromDependent() async throws {
        let index = try BuiltinTypeLayoutIndex(machO: machOImage)

        let fixedRecord = index.layout(forTypeName: "SymbolTestsCore.GenericFieldLayout.SpareBitsVariantEnum")
        #expect(fixedRecord != nil, "the argument-independent generic MPE must carry a builtin whole-type record")
        #expect(fixedRecord?.size == 24, "got \(String(describing: fixedRecord?.size))")
        #expect(fixedRecord?.stride == 24)
        #expect(fixedRecord?.extraInhabitantCount == 125, "got \(String(describing: fixedRecord?.extraInhabitantCount))")

        // Payloads are bare parameters → layout is argument-dependent → the
        // compiler emits no record and the runtime tagged formula is correct.
        let dependentRecord = index.layout(forTypeName: "SymbolTestsCore.GenericFieldLayout.TwoPayloadGenericEnum")
        #expect(dependentRecord == nil, "an argument-dependent generic MPE must not carry a builtin record")
    }

    /// Real-OS end-to-end: the survey types that exposed the wrong model.
    /// `AttributedString.Keys.SetIterator` and `SpatialEventCollection.Iterator`
    /// both embed a `Dictionary` iterator, whose `_Variant` enum is the
    /// spare-bits shape (40/40/XI 126 via libswiftCore's records). The offline
    /// engine over the dyld-cache file must match the realized runtime
    /// value-witness table exactly. Pinned to OS internals by name suffix — if
    /// a future OS removes both types the floor fails loudly and the targets
    /// need updating.
    @MainActor
    @Test func dyldCacheIteratorEmbeddingTypesMatchRuntimeValueWitnessTable() async throws {
        let targetNameSuffixes = ["AttributedString.Keys.SetIterator", "SpatialEventCollection.Iterator"]
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

        var verifiedTypeCount = 0
        for contextDescriptor in try rootFile.swift.contextDescriptors {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                descriptor.isStruct,
                !descriptor.typeContextDescriptor.layout.flags.isGeneric,
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: rootFile))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                targetNameSuffixes.contains(where: { qualifiedTypeName.hasSuffix($0) })
            else { continue }

            guard let runtime = Self.runtimeWitnessedLayout(ofQualifiedTypeName: qualifiedTypeName, in: runtimeImage) else {
                Issue.record("no runtime metadata for \(qualifiedTypeName)")
                continue
            }

            let staticLayout = try calculator.typeLayout(forDescriptor: descriptor)
            #expect(staticLayout.size == runtime.size, "\(qualifiedTypeName): static size \(staticLayout.size) != runtime \(runtime.size)")
            #expect(staticLayout.stride == runtime.stride, "\(qualifiedTypeName): static stride \(staticLayout.stride) != runtime \(runtime.stride)")
            #expect(staticLayout.alignment == runtime.alignment, "\(qualifiedTypeName): static alignment \(staticLayout.alignment) != runtime \(runtime.alignment)")
            #expect(
                staticLayout.extraInhabitantCount == runtime.extraInhabitantCount,
                "\(qualifiedTypeName): static XI \(staticLayout.extraInhabitantCount) != runtime \(runtime.extraInhabitantCount)"
            )
            verifiedTypeCount += 1
        }
        #expect(verifiedTypeCount >= 1, "expected to verify at least one iterator-embedding OS type, got \(verifiedTypeCount)")
    }

    // MARK: - Helpers

    /// Finds a fixture type descriptor by its fully-qualified name; fails the
    /// enclosing test with a rebuild hint when the fixture binary predates the
    /// type.
    @MainActor
    private func fixtureTypeDescriptor(named qualifiedTypeName: String) throws -> TypeContextDescriptorWrapper? {
        let machO = machOImage
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard
                (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)) == qualifiedTypeName
            else { continue }
            return descriptor
        }
        Issue.record("fixture type \(qualifiedTypeName) not found — rebuild SymbolTestsCore")
        return nil
    }

    /// Cross-checks a static layout against the type's live value-witness
    /// table.
    @MainActor
    private func expectRuntimeAgreement(
        _ staticLayout: StaticTypeLayout,
        for descriptor: TypeContextDescriptorWrapper
    ) throws {
        let machO = machOImage
        guard let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO) else { return }
        let response = try accessor(request: .init())
        let valueWitnessTable = try response.value.resolve(in: machO).valueWitnessTable(in: machO)
        #expect(Int(valueWitnessTable.layout.size) == staticLayout.size)
        #expect(Int(valueWitnessTable.layout.stride) == staticLayout.stride)
        #expect(Int(valueWitnessTable.layout.flags.alignment) == staticLayout.alignment)
        #expect(Int(valueWitnessTable.layout.numExtraInhabitants) == staticLayout.extraInhabitantCount)
        #expect(valueWitnessTable.layout.flags.isBitwiseTakable == staticLayout.isBitwiseTakable)
    }

    /// The realized runtime value-witness quintuple of a named type in a loaded
    /// image — the ground truth the offline engine is compared against.
    private static func runtimeWitnessedLayout(
        ofQualifiedTypeName qualifiedTypeName: String,
        in machO: MachOImage
    ) -> (size: Int, stride: Int, alignment: Int, extraInhabitantCount: Int)? {
        for contextDescriptor in (try? machO.swift.contextDescriptors) ?? [] {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)) == qualifiedTypeName,
                let accessor = try? descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO),
                let response = try? accessor(request: .init()),
                let metadata = try? response.value.resolve(in: machO),
                let valueWitnessTable = try? metadata.valueWitnessTable(in: machO)
            else { continue }
            return (
                size: Int(valueWitnessTable.layout.size),
                stride: Int(valueWitnessTable.layout.stride),
                alignment: Int(valueWitnessTable.layout.flags.alignment),
                extraInhabitantCount: Int(valueWitnessTable.layout.numExtraInhabitants)
            )
        }
        return nil
    }
}
