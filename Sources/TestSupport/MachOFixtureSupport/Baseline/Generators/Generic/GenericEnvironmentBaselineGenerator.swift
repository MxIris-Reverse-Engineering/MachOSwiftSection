import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/GenericEnvironmentBaseline.swift`.
///
/// `GenericEnvironment` is the runtime-side bookkeeping that the Swift
/// runtime uses while instantiating a generic type's metadata. It is
/// materialized from the descriptor's
/// `defaultInstantiationPattern` at runtime and is not directly surfaced by
/// the static `MachOFile` reader on any SymbolTestsCore type. The Suite
/// records only the registered member names and documents the missing
/// runtime coverage.
package enum GenericEnvironmentBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in GenericEnvironment.swift.
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
        // GenericEnvironment is materialized at runtime by the metadata
        // initialization machinery and is not surfaced by the static
        // MachOFile reader for SymbolTestsCore. The Suite documents the
        // missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericEnvironmentBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericEnvironmentBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
