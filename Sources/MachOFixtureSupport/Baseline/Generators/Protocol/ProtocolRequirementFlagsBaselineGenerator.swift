import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolRequirementFlagsBaseline.swift`.
///
/// `ProtocolRequirementFlags` is a 32-bit `OptionSet` packing the
/// requirement kind in its low nibble plus an `isInstance` and
/// `maybeAsync` bit. Its derived accessors:
///   - `kind` — splits the low nibble into `ProtocolRequirementKind`.
///   - `isCoroutine` — true for `readCoroutine`/`modifyCoroutine`.
///   - `isAsync` — `!isCoroutine && contains(.maybeAsync)`.
///   - `isInstance` — `contains(.isInstance)`.
///
/// Two pickers feed the baseline so multiple branches are witnessed:
///   - The first requirement of `ProtocolWitnessTableTest` (a method) —
///     surfaces a real, live flags value with kind = `.method`.
///   - Synthetic raw values for the remaining branches the live fixture
///     does not exercise (`.readCoroutine` for `isCoroutine`,
///     `.method | maybeAsync` for `isAsync`).
package enum ProtocolRequirementFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machO)
        let protocolType = try `Protocol`(descriptor: descriptor, in: machO)
        let firstRequirement = try required(protocolType.requirements.first)
        let liveFlags = firstRequirement.layout.flags

        let liveEntryExpr = emitEntryExpr(rawValue: liveFlags.rawValue)
        // Synthetic: `.readCoroutine` (kind = 5) — exercises `isCoroutine: true`.
        let coroutineEntryExpr = emitEntryExpr(rawValue: 0x5)
        // Synthetic: `.method | maybeAsync` (kind = 1, async bit) —
        // exercises `isAsync: true`.
        let asyncEntryExpr = emitEntryExpr(rawValue: 0x21)

        // Public members declared directly in ProtocolRequirementFlags.swift.
        // `init(rawValue:)` and `rawValue` come from the OptionSet conformance.
        // The `.isInstance` / `.maybeAsync` static OptionSet values are
        // captured via the `isInstance` accessor and `maybeAsync` static.
        let registered = [
            "init(rawValue:)",
            "isAsync",
            "isCoroutine",
            "isInstance",
            "kind",
            "maybeAsync",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolRequirementFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let kindRawValue: UInt8
                let isCoroutine: Bool
                let isAsync: Bool
                let isInstance: Bool
            }

            static let witnessTableMethod = \(raw: liveEntryExpr)

            static let readCoroutine = \(raw: coroutineEntryExpr)

            static let methodAsync = \(raw: asyncEntryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolRequirementFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = ProtocolRequirementFlags(rawValue: rawValue)
        let kindRawValue = flags.kind.rawValue
        let isCoroutine = flags.isCoroutine
        let isAsync = flags.isAsync
        let isInstance = flags.isInstance

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            isCoroutine: \(literal: isCoroutine),
            isAsync: \(literal: isAsync),
            isInstance: \(literal: isInstance)
        )
        """
        return expr.description
    }
}
