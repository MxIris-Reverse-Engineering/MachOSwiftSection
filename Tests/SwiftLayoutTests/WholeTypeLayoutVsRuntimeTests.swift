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
/// recomputes its whole-type `size` and `stride`.
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
/// Extra-inhabitant *counts* are deliberately **not** asserted here: several
/// leaf types the engine models approximately (unsafe pointers, class
/// references, reference-backed containers) report an XI count that differs
/// from the runtime's while remaining large enough to size every enclosing
/// aggregate correctly. Size/stride is the dimension that governs field
/// offsets and is a hard guarantee; exact XI parity for those leaves is a
/// separate, deeper goal. (Multi-payload enum XI *is* asserted exactly, in
/// `MultiPayloadEnumStructuralTests`.)
@Suite
final class WholeTypeLayoutVsRuntimeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private struct Mismatch: CustomStringConvertible {
        let typeName: String
        let runtime: (size: Int, stride: Int, alignment: Int)
        let staticLayout: (size: Int, stride: Int, alignment: Int)
        var description: String {
            "\(typeName): runtime=(size: \(runtime.size), stride: \(runtime.stride), alignment: \(runtime.alignment)) "
                + "static=(size: \(staticLayout.size), stride: \(staticLayout.stride), alignment: \(staticLayout.alignment))"
        }
    }

    @MainActor
    @Test func staticWholeTypeSizeStrideAlignmentMatchRuntime() async throws {
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
            let runtime: (size: Int, stride: Int, alignment: Int)
            do {
                let response = try accessor(request: .init())
                let metadata = try response.value.resolve(in: machO)
                let valueWitnessTable = try metadata.valueWitnessTable(in: machO)
                runtime = (
                    Int(valueWitnessTable.layout.size),
                    Int(valueWitnessTable.layout.stride),
                    Int(valueWitnessTable.layout.flags.alignment)
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

            let staticTriple = (staticLayout.size, staticLayout.stride, staticLayout.alignment)
            if staticTriple != runtime {
                let typeName = (try? descriptor.typeContextDescriptor.name(in: machO)) ?? qualifiedTypeName
                mismatches.append(Mismatch(typeName: typeName, runtime: runtime, staticLayout: staticTriple))
            }
        }

        #expect(comparedCount > 50, "expected to compare many fixture value types, got \(comparedCount)")
        // Guard the enum coverage this suite exists to add: the offset suite
        // skips enums, so a vacuous enum count would silently reopen the gap.
        #expect(enumCount >= 10, "expected to compare many fixture enums, got \(enumCount)")
        #expect(
            mismatches.isEmpty,
            Comment(rawValue: "whole-type size/stride/alignment mismatches:\n" + mismatches.map(\.description).joined(separator: "\n"))
        )
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
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        let qualifiedTypeName = "SymbolTestsCore.Enums.SinglePayloadOverStructTest"

        var found = false
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper, descriptor.isEnum else { continue }
            guard
                (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)) == qualifiedTypeName
            else { continue }
            found = true
            let staticLayout = try calculator.typeLayout(forDescriptor: descriptor)
            #expect(staticLayout.size == 8, "enum over struct-wrapping-class must be 8 bytes, got \(staticLayout.size)")
            #expect(staticLayout.stride == 8, "enum over struct-wrapping-class must have stride 8, got \(staticLayout.stride)")
            #expect(staticLayout.alignment == 8, "enum over struct-wrapping-class must be 8-aligned, got \(staticLayout.alignment)")

            // Cross-check against the runtime value-witness table.
            if let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO) {
                let response = try accessor(request: .init())
                let valueWitnessTable = try response.value.resolve(in: machO).valueWitnessTable(in: machO)
                #expect(Int(valueWitnessTable.layout.size) == staticLayout.size)
                #expect(Int(valueWitnessTable.layout.stride) == staticLayout.stride)
                #expect(Int(valueWitnessTable.layout.flags.alignment) == staticLayout.alignment)
            }
        }
        #expect(found, "fixture enum \(qualifiedTypeName) not found — rebuild SymbolTestsCore")
    }
}
