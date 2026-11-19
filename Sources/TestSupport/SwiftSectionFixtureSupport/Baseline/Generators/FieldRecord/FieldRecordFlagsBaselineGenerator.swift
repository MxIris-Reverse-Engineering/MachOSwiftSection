import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/FieldRecordFlagsBaseline.swift`.
///
/// `FieldRecordFlags` is a 32-bit `OptionSet` carried in every
/// `FieldRecord`'s leading `flags` field. It declares three orthogonal
/// option bits:
///   - `0x1` — `isIndirectCase`
///   - `0x2` — `isVariadic`
///   - `0x4` — `isArtificial`
/// The static `let`s collapse with their same-named OptionSet membership
/// checks under PublicMemberScanner's name-only key.
///
/// The baseline embeds canonical synthetic raw values exercising each
/// branch plus combinations.
package enum FieldRecordFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let empty = emitEntryExpr(rawValue: 0x0)
        let isIndirectCase = emitEntryExpr(rawValue: 0x1)
        let isVariadic = emitEntryExpr(rawValue: 0x2)
        let isArtificial = emitEntryExpr(rawValue: 0x4)
        let allBits = emitEntryExpr(rawValue: 0x7)

        // Public members declared directly in FieldRecordFlags.swift.
        let registered = [
            "init(rawValue:)",
            "isArtificial",
            "isIndirectCase",
            "isVariadic",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // FieldRecordFlags is exercised against synthetic raw values
        // covering each option bit (isIndirectCase / isVariadic /
        // isArtificial) plus the empty and all-bits combinations. Live
        // carriers are also exercised by the FieldRecord Suite's
        // per-fixture readings (the SymbolTestsCore fixture's records
        // all carry flags == 0x0).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FieldRecordFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let isIndirectCase: Bool
                let isVariadic: Bool
                let isArtificial: Bool
            }

            static let empty = \(raw: empty)

            static let isIndirectCase = \(raw: isIndirectCase)

            static let isVariadic = \(raw: isVariadic)

            static let isArtificial = \(raw: isArtificial)

            static let allBits = \(raw: allBits)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FieldRecordFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = FieldRecordFlags(rawValue: rawValue)
        let isIndirectCase = flags.contains(.isIndirectCase)
        let isVariadic = flags.contains(.isVariadic)
        let isArtificial = flags.contains(.isArtificial)

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            isIndirectCase: \(literal: isIndirectCase),
            isVariadic: \(literal: isVariadic),
            isArtificial: \(literal: isArtificial)
        )
        """
        return expr.description
    }
}
