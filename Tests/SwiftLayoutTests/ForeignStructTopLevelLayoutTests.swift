import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A C-imported (foreign) struct's Swift field records do not describe its
/// real C layout — bitfields and padding are invisible to reflection — so the
/// top-level `fieldLayout(of:)` entry must not trust a structural accumulation
/// that contradicts the authoritative `__swift5_builtin` whole-type record
/// (which the *field-type* resolution path already consults): `__C.Decimal`'s
/// records place `_mantissa` at 0 (really 4) and size the type 16 (really 20).
/// Discovered by a SwiftUI/SwiftUICore/SwiftData whole-framework survey against
/// the live runtime; `__C.PathData`-style record-less foreign structs came out
/// as size-0 aggregates through the same gap.
@Suite
final class ForeignStructTopLevelLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    @MainActor
    @Test func topLevelForeignStructTakesBuiltinWholeTypeLayout() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        var foundDescriptor = false
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard
                let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                descriptor.isStruct,
                let qualifiedTypeName = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                qualifiedTypeName == "__C.Decimal"
            else { continue }
            foundDescriptor = true

            let aggregate = try calculator.fieldLayout(of: descriptor)

            // Whole-type facts come from the `__swift5_builtin` record (pinned
            // by `BuiltinTypeLayoutTests` against the runtime value-witness
            // table): 20 bytes, 4-aligned — not the 16/2-aligned structural
            // accumulation of the bitfield-less Swift field records.
            #expect(aggregate.size == 20, "size \(aggregate.size)")
            #expect(aggregate.stride == 20, "stride \(aggregate.stride)")
            #expect(aggregate.alignment == 4, "alignment \(aggregate.alignment)")

            // The records omit the leading C bitfields, so no per-field offset
            // is derivable — every field must degrade rather than report a
            // confident wrong offset (`_mantissa` at 0; really at 4).
            for field in aggregate.fields {
                if case .computed = field.resolution {
                    Issue.record("foreign field \(field.fieldName) reported a computed offset \(field.offset)")
                }
            }
            break
        }
        #expect(foundDescriptor, "fixture image carries no __C.Decimal foreign descriptor")
    }
}
