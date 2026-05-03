import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/InvertibleProtocolSetBaseline.swift`.
///
/// `InvertibleProtocolSet` is a 16-bit `OptionSet` over the invertible
/// protocol kinds (`copyable`, `escapable`). Both `Copyable` and
/// `Escapable` are stdlib protocols with no `__swift5_protos` records of
/// their own (the bits are encoded inline on each type's
/// `RequirementInSignature`), so the baseline records canonical synthetic
/// raw values for each branch:
///   - default (`0x0`) — neither copyable nor escapable
///   - copyable only (`0x1`)
///   - escapable only (`0x2`)
///   - both (`0x3`) — exercises `hasCopyable && hasEscapable`
package enum InvertibleProtocolSetBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let noneEntry = emitEntryExpr(rawValue: 0x0)
        let copyableEntry = emitEntryExpr(rawValue: 0x1)
        let escapableEntry = emitEntryExpr(rawValue: 0x2)
        let bothEntry = emitEntryExpr(rawValue: 0x3)

        // Public members declared directly in InvertibleProtocolSet.swift.
        // `init(rawValue:)` and `rawValue` come from the OptionSet conformance.
        // The static `.copyable` / `.escapable` OptionSet values surface as
        // declared static vars.
        let registered = [
            "copyable",
            "escapable",
            "hasCopyable",
            "hasEscapable",
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // InvertibleProtocolSet has no live SymbolTestsCore source (the
        // Copyable/Escapable bits are encoded inline on type generic
        // signatures), so the baseline embeds synthetic raw values that
        // exercise each branch (none / copyable-only / escapable-only / both).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum InvertibleProtocolSetBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
                let hasCopyable: Bool
                let hasEscapable: Bool
            }

            static let none = \(raw: noneEntry)

            static let copyableOnly = \(raw: copyableEntry)

            static let escapableOnly = \(raw: escapableEntry)

            static let both = \(raw: bothEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("InvertibleProtocolSetBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt16) -> String {
        let set = InvertibleProtocolSet(rawValue: rawValue)
        let hasCopyable = set.hasCopyable
        let hasEscapable = set.hasEscapable

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            hasCopyable: \(literal: hasCopyable),
            hasEscapable: \(literal: hasEscapable)
        )
        """
        return expr.description
    }
}
