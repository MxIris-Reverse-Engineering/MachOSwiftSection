import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericEnvironmentFlagsBaseline.swift`.
///
/// `GenericEnvironmentFlags` is a 32-bit `OptionSet` that bit-packs two
/// counters into a single rawValue: the lowest 12 bits store
/// `numberOfGenericParameterLevels`; the next 16 bits (shifted by 12) store
/// `numberOfGenericRequirements`. The `SymbolTestsCore` fixture has no live
/// `GenericEnvironment` carrier (the structure is materialized by the
/// runtime's metadata initialization machinery, not the static descriptor
/// records), so the baseline embeds canonical synthetic raw values that
/// exercise both bit-fields together.
///
///   - `0x0` — both counters zero
///   - `0x1` — 1 parameter level, 0 requirements
///   - `0x1003` — 3 parameter levels, 1 requirement (`(1 << 12) | 0x3`)
///   - `0xfffff` — 0xFFF parameter levels (max), 0xFF requirements (`0xFF << 12 | 0xFFF`)
package enum GenericEnvironmentFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let zeroEntry = emitEntryExpr(rawValue: 0x0)
        let oneLevelEntry = emitEntryExpr(rawValue: 0x1)
        let threeLevelsOneReqEntry = emitEntryExpr(rawValue: 0x1003)
        let maxEntry = emitEntryExpr(rawValue: 0xFFFFF)

        // Public members declared directly in GenericEnvironmentFlags.swift.
        // `init(rawValue:)` is the OptionSet-synthesized initializer.
        let registered = [
            "init(rawValue:)",
            "numberOfGenericParameterLevels",
            "numberOfGenericRequirements",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // GenericEnvironmentFlags has no live SymbolTestsCore source (the
        // structure is materialized by the runtime's metadata initialization
        // machinery), so the baseline embeds synthetic raw values exercising
        // both bit-fields (parameter levels + requirements).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericEnvironmentFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let numberOfGenericParameterLevels: UInt32
                let numberOfGenericRequirements: UInt32
            }

            static let zero = \(raw: zeroEntry)

            static let oneLevel = \(raw: oneLevelEntry)

            static let threeLevelsOneRequirement = \(raw: threeLevelsOneReqEntry)

            static let maxAll = \(raw: maxEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericEnvironmentFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = GenericEnvironmentFlags(rawValue: rawValue)
        let levels = flags.numberOfGenericParameterLevels
        let requirements = flags.numberOfGenericRequirements

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            numberOfGenericParameterLevels: \(raw: BaselineEmitter.hex(levels)),
            numberOfGenericRequirements: \(raw: BaselineEmitter.hex(requirements))
        )
        """
        return expr.description
    }
}
