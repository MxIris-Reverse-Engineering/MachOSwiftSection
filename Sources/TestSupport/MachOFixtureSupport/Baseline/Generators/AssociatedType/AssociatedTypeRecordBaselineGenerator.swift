import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AssociatedTypeRecordBaseline.swift`.
///
/// `AssociatedTypeRecord` describes a single associated-type witness — its
/// `RelativeDirectPointer<String>` to the requirement name and its
/// `RelativeDirectPointer<MangledName>` to the substituted type. Beyond
/// the layout trio (`offset`, `layout`, `init(layout:offset:)` —
/// synthesized initializer is filtered) it carries two reader methods
/// (`name(in:)` and `substitutedTypeName(in:)`) plus their in-process
/// and ReadingContext overloads.
///
/// Picker: the first record from the
/// `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` ↔
/// `AssociatedPatternProtocol` descriptor (witnessing `First = Int`).
package enum AssociatedTypeRecordBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machO)
        let records = try descriptor.associatedTypeRecords(in: machO)
        let firstRecord = try required(records.first)

        let entryExpr = try emitEntryExpr(for: firstRecord, in: machO)

        // Public members declared directly in AssociatedTypeRecord.swift
        // (across the body and three same-file extensions: MachO + InProcess +
        // ReadingContext). Overload triples collapse to single MethodKey
        // entries under the scanner's name-based deduplication.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "name",
            "offset",
            "substitutedTypeName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite (AssociatedTypeRecordTests) verifies the methods
        // produce cross-reader-consistent results at runtime against the
        // name string / presence flags recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AssociatedTypeRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let name: String
                let hasSubstitutedTypeName: Bool
            }

            static let firstRecord = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AssociatedTypeRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for record: AssociatedTypeRecord,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = record.offset
        let name = try record.name(in: machO)
        let hasSubstitutedTypeName = (try? record.substitutedTypeName(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            name: \(literal: name),
            hasSubstitutedTypeName: \(literal: hasSubstitutedTypeName)
        )
        """
        return expr.description
    }
}
