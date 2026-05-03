import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericContextDescriptorFlagsBaseline.swift`.
///
/// `GenericContextDescriptorFlags` is a 16-bit `OptionSet` carried in the
/// `GenericContextDescriptorHeader` of every generic type's descriptor. The
/// three static option bits are `hasTypePacks`, `hasConditionalInvertedProtocols`,
/// and `hasValues`; their same-named instance forms (via OptionSet `contains`)
/// collapse to one MethodKey under PublicMemberScanner's name-only key.
///
/// The baseline embeds canonical synthetic raw values exercising each branch:
///   - default (`0x0`) — none set
///   - typePacks only (`0x1`)
///   - conditional inverted protocols only (`0x2`)
///   - values only (`0x4`)
///   - all three (`0x7`)
package enum GenericContextDescriptorFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let noneEntry = emitEntryExpr(rawValue: 0x0)
        let typePacksEntry = emitEntryExpr(rawValue: 0x1)
        let conditionalEntry = emitEntryExpr(rawValue: 0x2)
        let valuesEntry = emitEntryExpr(rawValue: 0x4)
        let allEntry = emitEntryExpr(rawValue: 0x7)

        // Public members declared directly in GenericContextDescriptorFlags.swift.
        // The three static `let`s collapse with their same-named OptionSet
        // membership checks under PublicMemberScanner's name-only key.
        let registered = [
            "hasConditionalInvertedProtocols",
            "hasTypePacks",
            "hasValues",
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // GenericContextDescriptorFlags is exercised against synthetic raw
        // values covering each option bit (none / typePacks / conditional /
        // values / all). The fixture has live carriers too — see the
        // GenericContextDescriptorHeader Suite for in-binary readings.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericContextDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
                let hasTypePacks: Bool
                let hasConditionalInvertedProtocols: Bool
                let hasValues: Bool
            }

            static let none = \(raw: noneEntry)

            static let typePacksOnly = \(raw: typePacksEntry)

            static let conditionalOnly = \(raw: conditionalEntry)

            static let valuesOnly = \(raw: valuesEntry)

            static let all = \(raw: allEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericContextDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt16) -> String {
        let flags = GenericContextDescriptorFlags(rawValue: rawValue)
        let hasTypePacks = flags.contains(.hasTypePacks)
        let hasConditionalInvertedProtocols = flags.contains(.hasConditionalInvertedProtocols)
        let hasValues = flags.contains(.hasValues)

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            hasTypePacks: \(literal: hasTypePacks),
            hasConditionalInvertedProtocols: \(literal: hasConditionalInvertedProtocols),
            hasValues: \(literal: hasValues)
        )
        """
        return expr.description
    }
}
