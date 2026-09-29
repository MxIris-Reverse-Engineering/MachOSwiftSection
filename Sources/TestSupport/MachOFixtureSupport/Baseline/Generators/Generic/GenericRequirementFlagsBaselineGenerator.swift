import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericRequirementFlagsBaseline.swift`.
///
/// `GenericRequirementFlags` is a 32-bit `OptionSet` carried in every
/// `GenericRequirementDescriptor`'s leading `flags` field. It packs a
/// `GenericRequirementKind` into the lowest 5 bits plus three orthogonal
/// option bits at higher offsets:
///   - `0x20` — `isPackRequirement`
///   - `0x80` — `hasKeyArgument`
///   - `0x100` — `isValueRequirement`
/// The static `let`s collapse with their same-named OptionSet membership
/// checks under PublicMemberScanner's name-only key.
///
/// The baseline embeds canonical synthetic raw values exercising each
/// branch of the kind decoder plus combinations with the option bits.
package enum GenericRequirementFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let protocolDefault = emitEntryExpr(rawValue: 0x0) // kind=protocol, no opts
        let sameType = emitEntryExpr(rawValue: 0x1) // kind=sameType
        let layoutOnly = emitEntryExpr(rawValue: 0x1F) // kind=layout (0x1F)
        let protocolWithKey = emitEntryExpr(rawValue: 0x80) // protocol + hasKeyArgument
        let packWithKey = emitEntryExpr(rawValue: 0xA0) // pack + hasKeyArgument
        let valueRequirement = emitEntryExpr(rawValue: 0x100) // isValueRequirement

        // Public members declared directly in GenericRequirementFlags.swift.
        let registered = [
            "hasKeyArgument",
            "init(rawValue:)",
            "isPackRequirement",
            "isValueRequirement",
            "kind",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // GenericRequirementFlags is exercised against synthetic raw values
        // covering each kind (protocol/sameType/layout) plus combinations
        // with the three option bits (isPackRequirement/hasKeyArgument/
        // isValueRequirement). Live carriers are also exercised by the
        // GenericRequirementDescriptor Suite's per-fixture readings.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericRequirementFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let kindRawValue: UInt8
                let isPackRequirement: Bool
                let hasKeyArgument: Bool
                let isValueRequirement: Bool
            }

            static let protocolDefault = \(raw: protocolDefault)

            static let sameType = \(raw: sameType)

            static let layoutOnly = \(raw: layoutOnly)

            static let protocolWithKey = \(raw: protocolWithKey)

            static let packWithKey = \(raw: packWithKey)

            static let valueRequirement = \(raw: valueRequirement)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericRequirementFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = GenericRequirementFlags(rawValue: rawValue)
        let kindRawValue = flags.kind.rawValue
        let isPackRequirement = flags.contains(.isPackRequirement)
        let hasKeyArgument = flags.contains(.hasKeyArgument)
        let isValueRequirement = flags.contains(.isValueRequirement)

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            isPackRequirement: \(literal: isPackRequirement),
            hasKeyArgument: \(literal: hasKeyArgument),
            isValueRequirement: \(literal: isValueRequirement)
        )
        """
        return expr.description
    }
}
