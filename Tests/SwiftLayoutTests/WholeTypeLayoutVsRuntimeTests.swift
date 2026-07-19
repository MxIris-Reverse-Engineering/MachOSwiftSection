import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The whole-type companion to `StaticLayoutVsRuntimeTests`: for every
/// non-generic **struct/enum** defined in the fixture module, materialize the
/// runtime value-witness table (the ground truth) and assert the static engine
/// recomputes its whole-type `size`, `stride`, `alignment`,
/// `extraInhabitantCount`, and bitwise-takability.
///
/// This closes two gaps the offset suite left open:
///
/// 1. **Enums are covered.** `StaticLayoutVsRuntimeTests` only iterates
///    struct/class (enums carry no field-offset vector), so a single-payload
///    enum's whole-type size was never checked against runtime. That is exactly
///    where the "under-reported payload extra inhabitants → spurious tag byte"
///    bug hides: an enum over a payload whose extra inhabitants were computed
///    too low (a struct that never propagated its field's XI, or `String`'s
///    frozen count set too small) gains a phantom tag byte and grows by one.
///
/// 2. **Whole-type size is checked directly**, not only transitively through a
///    later field's offset — so a mis-sized type is caught even when nothing
///    happens to sit after it.
///
/// Extra-inhabitant counts are asserted **exactly**: every leaf the engine
/// models now carries its true runtime count (managed pointers saturate at
/// 0x7FFF_FFFF on 64-bit Darwin, unsafe pointers reserve only null, weak
/// storage has none, unowned storage has exactly one), and every aggregate
/// rule (struct/tuple max-over-fields, the three enum strategies) is a ported
/// runtime formula — so any divergence from the live value-witness table is a
/// bug, not an approximation.
@Suite
final class WholeTypeLayoutVsRuntimeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private struct WitnessedLayout: Equatable, CustomStringConvertible {
        let size: Int
        let stride: Int
        let alignment: Int
        let extraInhabitantCount: Int
        let isBitwiseTakable: Bool
        var description: String {
            "(size: \(size), stride: \(stride), alignment: \(alignment), "
                + "extraInhabitantCount: 0x\(String(extraInhabitantCount, radix: 16)), "
                + "isBitwiseTakable: \(isBitwiseTakable))"
        }
    }

    private struct Mismatch: CustomStringConvertible {
        let typeName: String
        let runtime: WitnessedLayout
        let staticLayout: WitnessedLayout
        var description: String {
            "\(typeName): runtime=\(runtime) static=\(staticLayout)"
        }
    }

    private static func witnessedLayout(of staticLayout: StaticTypeLayout) -> WitnessedLayout {
        WitnessedLayout(
            size: staticLayout.size,
            stride: staticLayout.stride,
            alignment: staticLayout.alignment,
            extraInhabitantCount: staticLayout.extraInhabitantCount,
            isBitwiseTakable: staticLayout.isBitwiseTakable
        )
    }

    @MainActor
    @Test func staticWholeTypeLayoutMatchesRuntimeValueWitnessTable() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        var comparedCount = 0
        var enumCount = 0
        var mismatches: [Mismatch] = []

        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard !descriptor.typeContextDescriptor.layout.flags.isGeneric else { continue }
            // Value types only: a class *value* is a reference (pointer-sized),
            // its instance layout is validated field-by-field by the offset suite.
            guard descriptor.isStruct || descriptor.isEnum else { continue }
            guard
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                qualifiedTypeName.hasPrefix("SymbolTests")
            else { continue }

            // Ground truth: the runtime value-witness table.
            guard let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO) else { continue }
            let runtime: WitnessedLayout
            do {
                let response = try accessor(request: .init())
                let metadata = try response.value.resolve(in: machO)
                let valueWitnessTable = try metadata.valueWitnessTable(in: machO)
                runtime = WitnessedLayout(
                    size: Int(valueWitnessTable.layout.size),
                    stride: Int(valueWitnessTable.layout.stride),
                    alignment: Int(valueWitnessTable.layout.flags.alignment),
                    extraInhabitantCount: Int(valueWitnessTable.layout.numExtraInhabitants),
                    isBitwiseTakable: valueWitnessTable.layout.flags.isBitwiseTakable
                )
            } catch {
                continue
            }

            // The static engine may legitimately decline a type it cannot fully
            // resolve in single-image scope (existential/cross-module inner
            // types throw); those are out of scope here, not mismatches.
            guard let staticLayout = try? calculator.typeLayout(forDescriptor: descriptor) else { continue }

            comparedCount += 1
            if descriptor.isEnum { enumCount += 1 }

            let witnessed = Self.witnessedLayout(of: staticLayout)
            if witnessed != runtime {
                let typeName = (try? descriptor.typeContextDescriptor.name(in: machO)) ?? qualifiedTypeName
                mismatches.append(Mismatch(typeName: typeName, runtime: runtime, staticLayout: witnessed))
            }
        }

        #expect(comparedCount > 50, "expected to compare many fixture value types, got \(comparedCount)")
        // Guard the enum coverage this suite exists to add: the offset suite
        // skips enums, so a vacuous enum count would silently reopen the gap.
        #expect(enumCount >= 10, "expected to compare many fixture enums, got \(enumCount)")
        #expect(
            mismatches.isEmpty,
            Comment(rawValue: "whole-type layout mismatches:\n" + mismatches.map(\.description).joined(separator: "\n"))
        )
    }

    // MARK: - Targeted literal pins

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
    /// table in addition to the caller's literal expectations.
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

    /// The exact shape the user reported (a single-payload enum over a struct
    /// that wraps a class reference): the enum must stay a single pointer
    /// (size 8), because the struct inherits the reference's extra inhabitants
    /// and both empty cases fit in them. If struct extra inhabitants are dropped
    /// to zero (the regression), the enum spills into a tag byte → size 9,
    /// stride 16 — the same off-by-one that cascaded `Text.Style`'s field
    /// offsets. Pinned explicitly so the guarantee survives a fixture reshuffle.
    @MainActor
    @Test func singlePayloadEnumOverStructWrappingClassStaysPointerSized() async throws {
        guard let descriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.Enums.SinglePayloadOverStructTest") else { return }
        let calculator = try StaticLayoutCalculator(machO: machOImage)
        let staticLayout = try calculator.typeLayout(forDescriptor: descriptor)
        #expect(staticLayout.size == 8, "enum over struct-wrapping-class must be 8 bytes, got \(staticLayout.size)")
        #expect(staticLayout.stride == 8)
        #expect(staticLayout.alignment == 8)
        try expectRuntimeAgreement(staticLayout, for: descriptor)
    }

    /// A raw pointer reserves only null (extra-inhabitant count 1), so an enum
    /// with two empty cases over it must grow a tag byte: size 9, stride 16.
    /// The old saturated-approximation model (0x1000) absorbed both cases and
    /// mis-sized this enum to 8.
    @MainActor
    @Test func enumOverUnsafeRawPointerGrowsTagByte() async throws {
        guard let descriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.UnsafePointers.EnumOverUnsafeRawPointerTest") else { return }
        let calculator = try StaticLayoutCalculator(machO: machOImage)
        let staticLayout = try calculator.typeLayout(forDescriptor: descriptor)
        #expect(staticLayout.size == 9, "one of two empty cases must spill past the pointer's single extra inhabitant, got size \(staticLayout.size)")
        #expect(staticLayout.stride == 16)
        #expect(staticLayout.extraInhabitantCount == 0)
        try expectRuntimeAgreement(staticLayout, for: descriptor)
    }

    /// An optional thick function stays 16 bytes (the function-pointer word
    /// carries the saturated extra-inhabitant count), so a trailing field
    /// lands at offset 16 — the shape that regressed to 17/24 when the thick
    /// function's extra inhabitants were modelled as zero.
    @MainActor
    @Test func optionalThickFunctionKeepsTrailingFieldAtSixteen() async throws {
        guard let descriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.FunctionTypes.OptionalFunctionFieldTest") else { return }
        let calculator = try StaticLayoutCalculator(machO: machOImage)
        let staticLayout = try calculator.typeLayout(forDescriptor: descriptor)
        #expect(staticLayout.size == 17, "optional thick function (16) + trailing Int8 at 16, got size \(staticLayout.size)")
        #expect(staticLayout.stride == 24)
        let fieldLayout = try calculator.fieldLayout(of: descriptor)
        #expect(fieldLayout.fields.map(\.offset) == [0, 16], "trailing marker must land at 16, got \(fieldLayout.fields.map(\.offset))")
        try expectRuntimeAgreement(staticLayout, for: descriptor)
    }

    /// Weak storage: zero extra inhabitants (null is a legal live value) and
    /// not bitwise-takable (side-table registration pins the address); an enum
    /// with two empty cases over it spills both into a tag byte.
    @MainActor
    @Test func weakReferenceStructHasNoExtraInhabitantsAndIsNotBitwiseTakable() async throws {
        let calculator = try StaticLayoutCalculator(machO: machOImage)
        guard let structDescriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.WeakUnownedReferences.WeakReferenceStructTest") else { return }
        let structLayout = try calculator.typeLayout(forDescriptor: structDescriptor)
        #expect(structLayout.size == 8)
        #expect(structLayout.extraInhabitantCount == 0, "weak storage must expose no extra inhabitants, got \(structLayout.extraInhabitantCount)")
        #expect(structLayout.isBitwiseTakable == false)
        try expectRuntimeAgreement(structLayout, for: structDescriptor)

        guard let enumDescriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.WeakUnownedReferences.EnumOverWeakReferenceStructTest") else { return }
        let enumLayout = try calculator.typeLayout(forDescriptor: enumDescriptor)
        #expect(enumLayout.size == 9, "both empty cases must spill over a zero-extra-inhabitant payload, got size \(enumLayout.size)")
        try expectRuntimeAgreement(enumLayout, for: enumDescriptor)
    }

    /// Unowned (safe) storage: exactly one extra inhabitant — the
    /// ObjC-interop-conservative IRGen lowering ("null is the only extra
    /// inhabitant allowed"), *not* the underlying reference's saturated count
    /// that RemoteInspection's `TypeLowering.cpp` claims. An enum with two
    /// empty cases over it fits one and spills the other: size 9.
    @MainActor
    @Test func unownedReferenceStructHasExactlyOneExtraInhabitant() async throws {
        let calculator = try StaticLayoutCalculator(machO: machOImage)
        guard let structDescriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.WeakUnownedReferences.UnownedReferenceStructTest") else { return }
        let structLayout = try calculator.typeLayout(forDescriptor: structDescriptor)
        #expect(structLayout.size == 8)
        #expect(structLayout.extraInhabitantCount == 1, "unowned storage must expose exactly one extra inhabitant, got \(structLayout.extraInhabitantCount)")
        try expectRuntimeAgreement(structLayout, for: structDescriptor)

        guard let enumDescriptor = try fixtureTypeDescriptor(named: "SymbolTestsCore.WeakUnownedReferences.EnumOverUnownedReferenceStructTest") else { return }
        let enumLayout = try calculator.typeLayout(forDescriptor: enumDescriptor)
        #expect(enumLayout.size == 9, "the second empty case must spill past the single extra inhabitant, got size \(enumLayout.size)")
        try expectRuntimeAgreement(enumLayout, for: enumDescriptor)
    }
}
