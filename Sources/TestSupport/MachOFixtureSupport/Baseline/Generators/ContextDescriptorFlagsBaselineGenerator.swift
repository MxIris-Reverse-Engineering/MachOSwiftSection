import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorFlagsBaseline.swift`.
///
/// `ContextDescriptorFlags` is the bit-packed `OptionSet` carried in every
/// descriptor's first 4 bytes. The instance vars (`kind`, `version`,
/// `kindSpecificFlagsRawValue`, `kindSpecificFlags`, `hasInvertibleProtocols`,
/// `isUnique`, `isGeneric`) all derive from `rawValue`; the three static
/// `let`s (`hasInvertibleProtocols`, `isUnique`, `isGeneric`) collapse with
/// the instance vars under PublicMemberScanner's name-only key.
///
/// We sample the flags off the fixture's `Structs.StructTest` descriptor —
/// a struct kind whose `kindSpecificFlags` resolves to the `.type(...)`
/// case (carrying a `TypeContextDescriptorFlags` payload).
package enum ContextDescriptorFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let flags = descriptor.layout.flags
        let entryExpr = emitEntryExpr(for: flags)

        // Public members declared directly in ContextDescriptorFlags.swift.
        // The three static `let`s (`hasInvertibleProtocols`, `isUnique`,
        // `isGeneric`) and their same-named derived instance vars collapse
        // to single MethodKey entries.
        let registered = [
            "hasInvertibleProtocols",
            "init(rawValue:)",
            "isGeneric",
            "isUnique",
            "kind",
            "kindSpecificFlags",
            "kindSpecificFlagsRawValue",
            "rawValue",
            "version",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let kindRawValue: UInt8
                let version: UInt8
                let kindSpecificFlagsRawValue: UInt16
                let hasKindSpecificFlags: Bool
                let hasInvertibleProtocols: Bool
                let isUnique: Bool
                let isGeneric: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: ContextDescriptorFlags) -> String {
        let rawValue = flags.rawValue
        let kindRawValue = flags.kind.rawValue
        let version = flags.version
        let kindSpecificFlagsRawValue = flags.kindSpecificFlagsRawValue
        let hasKindSpecificFlags = flags.kindSpecificFlags != nil
        let hasInvertibleProtocols = flags.hasInvertibleProtocols
        let isUnique = flags.isUnique
        let isGeneric = flags.isGeneric

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            version: \(raw: BaselineEmitter.hex(version)),
            kindSpecificFlagsRawValue: \(raw: BaselineEmitter.hex(kindSpecificFlagsRawValue)),
            hasKindSpecificFlags: \(literal: hasKindSpecificFlags),
            hasInvertibleProtocols: \(literal: hasInvertibleProtocols),
            isUnique: \(literal: isUnique),
            isGeneric: \(literal: isGeneric)
        )
        """
        return expr.description
    }
}
