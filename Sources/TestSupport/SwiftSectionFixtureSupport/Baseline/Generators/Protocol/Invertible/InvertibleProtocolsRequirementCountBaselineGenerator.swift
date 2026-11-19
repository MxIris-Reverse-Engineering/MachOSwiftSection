import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/InvertibleProtocolsRequirementCountBaseline.swift`.
///
/// `InvertibleProtocolsRequirementCount` is a thin `RawRepresentable`
/// wrapper around a `UInt16` count of invertible-protocol requirements
/// in a generic signature. It surfaces no derived accessors — the public
/// API is the synthesized `init(rawValue:)` plus the `rawValue` storage.
///
/// The fixture has no live count to source from (the count is implied by
/// the surrounding requirement-signature scan, not stored as a separate
/// value), so the baseline records a synthetic round-trip pair.
package enum InvertibleProtocolsRequirementCountBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let zeroEntry = emitEntryExpr(rawValue: 0)
        let smallEntry = emitEntryExpr(rawValue: 3)

        // Public members declared directly in InvertibleProtocolsRequirementCount.swift.
        let registered = [
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // InvertibleProtocolsRequirementCount has no live SymbolTestsCore
        // source (the count is implied by the surrounding requirement
        // scan), so the baseline embeds synthetic raw values.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum InvertibleProtocolsRequirementCountBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
            }

            static let zero = \(raw: zeroEntry)

            static let small = \(raw: smallEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("InvertibleProtocolsRequirementCountBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt16) -> String {
        let count = InvertibleProtocolsRequirementCount(rawValue: rawValue)

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(count.rawValue))
        )
        """
        return expr.description
    }
}
