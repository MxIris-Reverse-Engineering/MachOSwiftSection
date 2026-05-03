import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/FieldDescriptorBaseline.swift`.
///
/// `FieldDescriptor` describes the per-type field-layout payload referenced
/// from a `TypeContextDescriptor` (and resolved via
/// `TypeContextDescriptorProtocol.fieldDescriptor(in:)`). Beyond the layout
/// trio (`offset`, `layout`, `init(layout:offset:)` — the synthesized
/// initializer is filtered) it carries one derived var (`kind`) and two
/// reader methods (`mangledTypeName(in:)`, `records(in:)`) plus their
/// in-process and ReadingContext overloads.
///
/// Picker variants:
///   - `GenericStructNonRequirement<A>` — three concrete fields
///     (`field1: Double`, `field2: A`, `field3: Int`). Exercises the
///     non-trivial records-array branch.
///   - `StructTest` — zero stored properties (the public `body` is a
///     computed property, which doesn't surface in the field descriptor).
///     Exercises the empty-records-array branch.
///
/// We pin: descriptor offset, kind raw value, records count, and the
/// per-field count of mangled-name / field-name pairs (recorded in
/// the FieldRecord Suite separately; here we just record the count).
package enum FieldDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let genericDescriptor = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO)
        let genericFieldDescriptor = try required(try genericDescriptor.fieldDescriptor(in: machO))

        let structTestDescriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let structTestFieldDescriptor = try required(try structTestDescriptor.fieldDescriptor(in: machO))

        let genericExpr = try emitEntryExpr(for: genericFieldDescriptor, in: machO)
        let structTestExpr = try emitEntryExpr(for: structTestFieldDescriptor, in: machO)

        // Public members declared directly in FieldDescriptor.swift (across
        // the body and three same-file extensions: MachO + InProcess +
        // ReadingContext). Overload triples collapse to single MethodKey
        // entries under the scanner's name-based deduplication.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "kind",
            "layout",
            "mangledTypeName",
            "offset",
            "records",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite (FieldDescriptorTests) verifies the methods
        // produce cross-reader-consistent results at runtime against the
        // presence flags / counts recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FieldDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let kindRawValue: UInt16
                let layoutNumFields: Int
                let layoutFieldRecordSize: Int
                let recordsCount: Int
                let hasMangledTypeName: Bool
            }

            static let genericStructNonRequirement = \(raw: genericExpr)

            static let structTest = \(raw: structTestExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FieldDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: FieldDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let kindRawValue = descriptor.layout.kind
        let layoutNumFields = Int(descriptor.layout.numFields)
        let layoutFieldRecordSize = Int(descriptor.layout.fieldRecordSize)
        let records = try descriptor.records(in: machO)
        let recordsCount = records.count
        let hasMangledTypeName = (try? descriptor.mangledTypeName(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            layoutNumFields: \(literal: layoutNumFields),
            layoutFieldRecordSize: \(literal: layoutFieldRecordSize),
            recordsCount: \(literal: recordsCount),
            hasMangledTypeName: \(literal: hasMangledTypeName)
        )
        """
        return expr.description
    }
}
