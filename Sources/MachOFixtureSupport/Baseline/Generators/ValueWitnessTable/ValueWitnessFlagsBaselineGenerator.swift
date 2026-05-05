import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ValueWitnessFlagsBaseline.swift`.
///
/// `ValueWitnessFlags` is a 32-bit `OptionSet` carried in every
/// `ValueWitnessTable` / `TypeLayout`. The bit layout:
///   - low 8 bits — `alignmentMask` (alignment - 1)
///   - bit 16 — `isNonPOD`
///   - bit 17 — `isNonInline`
///   - bit 19 — `hasSpareBits`
///   - bit 20 — `isNonBitwiseTakable`
///   - bit 21 — `hasEnumWitnesses`
///   - bit 22 — `inComplete`
///   - bit 23 — `isNonCopyable`
///   - bit 24 — `isNonBitwiseBorrowable`
///
/// The flags type is reader-independent — the Suite re-evaluates each
/// accessor against synthetic raw values.
package enum ValueWitnessFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let entries: [(label: String, rawValue: UInt32)] = [
            // POD value type: alignment 8 (mask 7), inline storage,
            // bitwise-takable, copyable.
            ("podStruct", 0x0000_0007),
            // Non-POD class instance: alignment 8 (mask 7), inline,
            // not bitwise-takable, not copyable, has-enum-witnesses
            // off.
            ("nonPodReference", 0x0011_0007),
            // Out-of-line storage (non-inline): alignment 8.
            ("nonInlineStorage", 0x0002_0007),
            // Has enum witnesses + spare bits.
            ("enumWithSpareBits", 0x0028_0007),
            // Incomplete (still being initialized).
            ("incomplete", 0x0040_0007),
            // Non-copyable (~Copyable).
            ("nonCopyable", 0x0080_0007),
            // Non-bitwise-borrowable.
            ("nonBitwiseBorrowable", 0x0100_0007),
        ]
        let entriesExpr = emitEntriesExpr(for: entries)

        // Public members declared in ValueWitnessFlags.swift. The
        // OptionSet `static let` constants collapse into the
        // option-set membership accessors under PublicMemberScanner's
        // name-only key (e.g. `isNonPOD` and the `static let isNonPOD`
        // share the name). We register each unique name once.
        let registered = [
            "alignment",
            "alignmentMask",
            "hasEnumWitnesses",
            "hasSpareBits",
            "inComplete",
            "init(rawValue:)",
            "isBitwiseBorrowable",
            "isBitwiseTakable",
            "isCopyable",
            "isIncomplete",
            "isInlineStorage",
            "isNonBitwiseBorrowable",
            "isNonBitwiseTakable",
            "isNonCopyable",
            "isNonInline",
            "isNonPOD",
            "isPOD",
            "maxNumExtraInhabitants",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ValueWitnessFlags is a pure raw-value bit decoder (no MachO
        // dependency). The baseline embeds canonical synthetic raw
        // values exercising each documented bit field.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ValueWitnessFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let alignmentMask: UInt64
                let alignment: UInt64
                let isPOD: Bool
                let isInlineStorage: Bool
                let isBitwiseTakable: Bool
                let isBitwiseBorrowable: Bool
                let isCopyable: Bool
                let hasEnumWitnesses: Bool
                let isIncomplete: Bool
            }

            static let cases: [Entry] = \(raw: entriesExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ValueWitnessFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntriesExpr(for entries: [(label: String, rawValue: UInt32)]) -> String {
        let lines = entries.map { entry -> String in
            let flags = ValueWitnessFlags(rawValue: entry.rawValue)
            return """
            // \(entry.label)
            Entry(
                rawValue: \(BaselineEmitter.hex(entry.rawValue)),
                alignmentMask: \(BaselineEmitter.hex(flags.alignmentMask)),
                alignment: \(BaselineEmitter.hex(flags.alignment)),
                isPOD: \(flags.isPOD),
                isInlineStorage: \(flags.isInlineStorage),
                isBitwiseTakable: \(flags.isBitwiseTakable),
                isBitwiseBorrowable: \(flags.isBitwiseBorrowable),
                isCopyable: \(flags.isCopyable),
                hasEnumWitnesses: \(flags.hasEnumWitnesses),
                isIncomplete: \(flags.isIncomplete)
            )
            """
        }
        return "[\n\(lines.joined(separator: ",\n"))\n]"
    }
}
