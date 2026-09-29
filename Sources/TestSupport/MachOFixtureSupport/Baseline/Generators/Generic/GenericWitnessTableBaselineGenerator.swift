import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/GenericWitnessTableBaseline.swift`.
///
/// `GenericWitnessTable` is the per-conformance witness-table layout
/// emitted alongside generic protocol conformances. It records the
/// witness table size, instantiator/private-data hooks. The structure is
/// reachable from a `ProtocolConformanceDescriptor`'s
/// `GenericWitnessTableSection` trailing object, but the
/// `SymbolTestsCore` fixture does NOT surface any conformance whose
/// witness-table layout reaches the parser as a `GenericWitnessTable`
/// instance through the current public API.
///
/// Until the upstream parser exposes a discoverable carrier, the Suite
/// records only the registered member names and documents the missing
/// runtime coverage.
package enum GenericWitnessTableBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in GenericWitnessTable.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // GenericWitnessTable is not surfaced by the current public API
        // for any SymbolTestsCore conformance. The Suite documents the
        // missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericWitnessTableBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericWitnessTableBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
