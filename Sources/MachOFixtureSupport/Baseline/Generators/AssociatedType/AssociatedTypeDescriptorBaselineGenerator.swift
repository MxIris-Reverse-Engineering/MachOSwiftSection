import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AssociatedTypeDescriptorBaseline.swift`.
///
/// `AssociatedTypeDescriptor` is the raw `__swift5_assocty` payload
/// describing a single conforming-type ↔ protocol pair plus the trailing
/// `[AssociatedTypeRecord]`. Beyond the layout trio (`offset`, `layout`,
/// `init(layout:offset:)` — synthesized initializer is filtered) and the
/// `TopLevelDescriptor` conformance (`actualSize`), it carries three
/// reader methods (`conformingTypeName(in:)`, `protocolTypeName(in:)`,
/// `associatedTypeRecords(in:)`) plus their in-process and ReadingContext
/// overloads.
///
/// Picker: `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` conforming
/// to `AssociatedTypeWitnessPatterns.AssociatedPatternProtocol` (five
/// concrete witnesses).
package enum AssociatedTypeDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machO)
        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared directly in AssociatedTypeDescriptor.swift
        // (across the body and three same-file extensions: MachO + InProcess +
        // ReadingContext, plus the `TopLevelDescriptor` conformance extension).
        // Overload triples collapse to single MethodKey entries under the
        // scanner's name-based deduplication. `init(layout:offset:)` is
        // filtered as memberwise-synthesized.
        let registered = [
            "actualSize",
            "associatedTypeRecords",
            "conformingTypeName",
            "layout",
            "offset",
            "protocolTypeName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite (AssociatedTypeDescriptorTests) verifies the
        // methods produce cross-reader-consistent results at runtime
        // against the counts / presence flags recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AssociatedTypeDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumAssociatedTypes: UInt32
                let layoutAssociatedTypeRecordSize: UInt32
                let actualSize: Int
                let recordsCount: Int
                let hasConformingTypeName: Bool
                let hasProtocolTypeName: Bool
            }

            static let concreteWitnessTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AssociatedTypeDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: AssociatedTypeDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let layoutNumAssociatedTypes = descriptor.layout.numAssociatedTypes
        let layoutAssociatedTypeRecordSize = descriptor.layout.associatedTypeRecordSize
        let actualSize = descriptor.actualSize
        let records = try descriptor.associatedTypeRecords(in: machO)
        let recordsCount = records.count
        let hasConformingTypeName = (try? descriptor.conformingTypeName(in: machO)) != nil
        let hasProtocolTypeName = (try? descriptor.protocolTypeName(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumAssociatedTypes: \(literal: layoutNumAssociatedTypes),
            layoutAssociatedTypeRecordSize: \(literal: layoutAssociatedTypeRecordSize),
            actualSize: \(literal: actualSize),
            recordsCount: \(literal: recordsCount),
            hasConformingTypeName: \(literal: hasConformingTypeName),
            hasProtocolTypeName: \(literal: hasProtocolTypeName)
        )
        """
        return expr.description
    }
}
