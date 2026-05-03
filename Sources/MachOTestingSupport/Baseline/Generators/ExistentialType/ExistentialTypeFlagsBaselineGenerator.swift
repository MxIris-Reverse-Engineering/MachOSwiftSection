import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExistentialTypeFlagsBaseline.swift`.
///
/// `ExistentialTypeFlags` is a 32-bit `OptionSet` carried in the leading
/// `flags` field of `ExistentialTypeMetadata` /
/// `ExistentialMetatypeMetadata`. The bits are:
///   - low 24 bits — `numberOfWitnessTables` (per-protocol witness count)
///   - bit 30 — `hasSuperclassConstraint`
///   - bits 24-29 — `specialProtocol` raw value (0 = none, 1 = error)
///   - bit 31 — `classConstraint` selector
///
/// The flags type is reader-independent (a pure raw-value bit decoder),
/// so the baseline embeds canonical synthetic raw values exercising each
/// branch.
///
/// Note: the `classConstraint` accessor in source applies an
/// `UInt8.init(rawValue & 0x8000_0000)` conversion that would trap when
/// bit 31 is set. We therefore only encode raw values with bit 31 clear,
/// i.e. exercise the `.class` arm of `ProtocolClassConstraint`. A
/// future fix to the accessor (mask-and-shift to 1 bit) would let the
/// `.any` arm be added.
package enum ExistentialTypeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let entries: [(label: String, rawValue: UInt32)] = [
            // Empty flags — class-bound, no witness tables.
            ("empty", 0x0000_0000),
            // Class-bound with one protocol witness table.
            ("classBoundOneWitness", 0x0000_0001),
            // Class-bound with three witness tables (composition `&`).
            ("classBoundThreeWitnesses", 0x0000_0003),
            // Error-special-protocol bit set, otherwise empty.
            ("errorSpecial", 0x0100_0000),
            // Has-superclass-constraint bit set.
            ("withSuperclass", 0x4000_0001),
        ]
        let entriesExpr = emitEntriesExpr(for: entries)

        // Public members declared directly in ExistentialTypeFlags.swift.
        let registered = [
            "classConstraint",
            "hasSuperclassConstraint",
            "init(rawValue:)",
            "numberOfWitnessTables",
            "rawValue",
            "specialProtocol",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExistentialTypeFlags is a pure raw-value bit decoder (no MachO
        // dependency). The baseline embeds canonical synthetic raw values
        // exercising each documented bit field.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialTypeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let numberOfWitnessTables: UInt32
                let classConstraintRawValue: UInt8
                let hasSuperclassConstraint: Bool
                let specialProtocolRawValue: UInt8
            }

            static let cases: [Entry] = \(raw: entriesExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialTypeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntriesExpr(for entries: [(label: String, rawValue: UInt32)]) -> String {
        let lines = entries.map { entry -> String in
            let flags = ExistentialTypeFlags(rawValue: entry.rawValue)
            return """
            // \(entry.label)
            Entry(
                rawValue: \(BaselineEmitter.hex(entry.rawValue)),
                numberOfWitnessTables: \(BaselineEmitter.hex(flags.numberOfWitnessTables)),
                classConstraintRawValue: \(BaselineEmitter.hex(flags.classConstraint.rawValue)),
                hasSuperclassConstraint: \(flags.hasSuperclassConstraint),
                specialProtocolRawValue: \(BaselineEmitter.hex(flags.specialProtocol.rawValue))
            )
            """
        }
        return "[\n\(lines.joined(separator: ",\n"))\n]"
    }
}
