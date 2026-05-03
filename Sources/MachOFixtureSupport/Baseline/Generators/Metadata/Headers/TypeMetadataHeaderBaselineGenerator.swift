import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/TypeMetadataHeaderBaseline.swift`.
///
/// `TypeMetadataHeader` is the (`layoutString`, `valueWitnesses`) prefix
/// preceding value-type metadata records. Live header instances are
/// materialised through `MetadataProtocol.asFullMetadata` from a MachOImage
/// metadata accessor; live pointer values are not embedded.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum TypeMetadataHeaderBaselineGenerator {
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
        // TypeMetadataHeader is materialised from MachOImage's accessor
        // (via FullMetadata header projection); live pointer values aren't
        // embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeMetadataHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeMetadataHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
