import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/EnumDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `EnumDescriptor` carries the `offset`/`layout` ivars (the
/// `init(layout:offset:)` initializer is filtered as memberwise-synthesized)
/// plus a long set of derived `var`s split across two same-file extensions:
/// the case-count accessors (`numberOfCases`, `numberOfEmptyCases`,
/// `numberOfPayloadCases`, `payloadSizeOffset`, `hasPayloadSizeOffset`) and
/// the predicate family (`isSingleEmptyCaseOnly`, `isSinglePayloadCaseOnly`,
/// `isSinglePayload`, `isMultiPayload`, `hasPayloadCases`).
///
/// Three pickers feed the baseline so each predicate's true branch is
/// witnessed by at least one entry: `NoPayloadEnumTest` (4 empty cases,
/// no payload), `SinglePayloadEnumTest` (one payload case + two empty
/// cases — the canonical `isSinglePayload` case), and `MultiPayloadEnumTests`
/// (4 cases, 3 payloads — the canonical `isMultiPayload` case).
package enum EnumDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let noPayload = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machO)
        let singlePayload = try BaselineFixturePicker.enum_SinglePayloadEnumTest(in: machO)
        let multiPayload = try BaselineFixturePicker.enum_MultiPayloadEnumTest(in: machO)

        let noPayloadExpr = emitEntryExpr(for: noPayload)
        let singlePayloadExpr = emitEntryExpr(for: singlePayload)
        let multiPayloadExpr = emitEntryExpr(for: multiPayload)

        // Members directly declared in EnumDescriptor.swift (across the main
        // body and two same-file extensions).
        let registered = [
            "hasPayloadCases",
            "hasPayloadSizeOffset",
            "isMultiPayload",
            "isSingleEmptyCaseOnly",
            "isSinglePayload",
            "isSinglePayloadCaseOnly",
            "layout",
            "numberOfCases",
            "numberOfEmptyCases",
            "numberOfPayloadCases",
            "offset",
            "payloadSizeOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum EnumDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumPayloadCasesAndPayloadSizeOffset: UInt32
                let layoutNumEmptyCases: UInt32
                let layoutFlagsRawValue: UInt32
                let numberOfCases: Int
                let numberOfEmptyCases: Int
                let numberOfPayloadCases: Int
                let payloadSizeOffset: Int
                let hasPayloadSizeOffset: Bool
                let isSingleEmptyCaseOnly: Bool
                let isSinglePayloadCaseOnly: Bool
                let isSinglePayload: Bool
                let isMultiPayload: Bool
                let hasPayloadCases: Bool
            }

            static let noPayloadEnumTest = \(raw: noPayloadExpr)

            static let singlePayloadEnumTest = \(raw: singlePayloadExpr)

            static let multiPayloadEnumTest = \(raw: multiPayloadExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("EnumDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for descriptor: EnumDescriptor) -> String {
        let offset = descriptor.offset
        let numPayloadCasesAndPayloadSizeOffset = descriptor.layout.numPayloadCasesAndPayloadSizeOffset
        let numEmptyCases = descriptor.layout.numEmptyCases
        let flagsRaw = descriptor.layout.flags.rawValue
        let numberOfCases = descriptor.numberOfCases
        let numberOfEmptyCases = descriptor.numberOfEmptyCases
        let numberOfPayloadCases = descriptor.numberOfPayloadCases
        let payloadSizeOffset = descriptor.payloadSizeOffset
        let hasPayloadSizeOffset = descriptor.hasPayloadSizeOffset
        let isSingleEmptyCaseOnly = descriptor.isSingleEmptyCaseOnly
        let isSinglePayloadCaseOnly = descriptor.isSinglePayloadCaseOnly
        let isSinglePayload = descriptor.isSinglePayload
        let isMultiPayload = descriptor.isMultiPayload
        let hasPayloadCases = descriptor.hasPayloadCases

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumPayloadCasesAndPayloadSizeOffset: \(raw: BaselineEmitter.hex(numPayloadCasesAndPayloadSizeOffset)),
            layoutNumEmptyCases: \(raw: BaselineEmitter.hex(numEmptyCases)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
            numberOfCases: \(literal: numberOfCases),
            numberOfEmptyCases: \(literal: numberOfEmptyCases),
            numberOfPayloadCases: \(literal: numberOfPayloadCases),
            payloadSizeOffset: \(literal: payloadSizeOffset),
            hasPayloadSizeOffset: \(literal: hasPayloadSizeOffset),
            isSingleEmptyCaseOnly: \(literal: isSingleEmptyCaseOnly),
            isSinglePayloadCaseOnly: \(literal: isSinglePayloadCaseOnly),
            isSinglePayload: \(literal: isSinglePayload),
            isMultiPayload: \(literal: isMultiPayload),
            hasPayloadCases: \(literal: hasPayloadCases)
        )
        """
        return expr.description
    }
}
