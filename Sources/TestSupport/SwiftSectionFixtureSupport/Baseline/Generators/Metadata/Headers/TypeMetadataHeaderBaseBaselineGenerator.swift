import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/TypeMetadataHeaderBaseBaseline.swift`.
///
/// `TypeMetadataHeaderBase` is the minimal value-witness-pointer prefix
/// (just the `valueWitnesses` field) shared by every metadata header
/// hierarchy. Live header instances are materialised through MachOImage's
/// accessor; live pointer values are not embedded.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum TypeMetadataHeaderBaseBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // TypeMetadataHeaderBase is materialised from MachOImage's accessor
        // (via FullMetadata header projection); live pointer values aren't
        // embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeMetadataHeaderBaseBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeMetadataHeaderBaseBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
