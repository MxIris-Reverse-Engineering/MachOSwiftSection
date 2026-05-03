import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/FieldRecordBaseline.swift`.
///
/// `FieldRecord` describes a single field declared by a Swift type — its
/// `RelativeDirectPointer<MangledName>` to the field's type and a
/// `RelativeDirectPointer<String>` to its source name. Beyond the layout
/// trio (`offset`, `layout`, `init(layout:offset:)` — synthesized initializer
/// is filtered) it carries two reader methods (`mangledTypeName(in:)` and
/// `fieldName(in:)`) plus their in-process and ReadingContext overloads.
///
/// Picker: `GenericStructNonRequirement<A>`'s field descriptor surfaces
/// three records (`field1`, `field2`, `field3`). We pin the first two
/// to exercise both a concrete-type field (`field1: Double`) and a
/// generic-parameter field (`field2: A`).
package enum FieldRecordBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO)
        let fieldDescriptor = try required(try descriptor.fieldDescriptor(in: machO))
        let records = try fieldDescriptor.records(in: machO)

        let firstRecord = try required(records.first)
        let secondRecord = try required(records.dropFirst().first)

        let firstExpr = try emitEntryExpr(for: firstRecord, in: machO)
        let secondExpr = try emitEntryExpr(for: secondRecord, in: machO)

        // Public members declared directly in FieldRecord.swift (across the
        // body and three same-file extensions: MachO + InProcess +
        // ReadingContext). Overload triples collapse to single MethodKey
        // entries under the scanner's name-based deduplication.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "fieldName",
            "layout",
            "mangledTypeName",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite (FieldRecordTests) verifies the methods produce
        // cross-reader-consistent results at runtime against the field
        // names / presence flags recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FieldRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let fieldName: String
                let hasMangledTypeName: Bool
            }

            static let firstRecord = \(raw: firstExpr)

            static let secondRecord = \(raw: secondExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FieldRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for record: FieldRecord,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = record.offset
        let layoutFlagsRawValue = record.layout.flags.rawValue
        let fieldName = try record.fieldName(in: machO)
        let hasMangledTypeName = (try? record.mangledTypeName(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(layoutFlagsRawValue)),
            fieldName: \(literal: fieldName),
            hasMangledTypeName: \(literal: hasMangledTypeName)
        )
        """
        return expr.description
    }
}
