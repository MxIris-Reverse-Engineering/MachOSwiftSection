import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/AnyClassMetadataBaseline.swift`.
///
/// Like the Struct counterparts, the class metadata types must be
/// materialised at runtime via the MachOImage metadata accessor; live
/// pointer values are not stable across runs and aren't embedded as
/// literals. The Suite (`AnyClassMetadataTests`) exercises cross-reader
/// consistency at runtime against this name-only baseline.
package enum AnyClassMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in AnyClassMetadata.swift.
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
        // AnyClassMetadata can only be obtained by chasing superclass
        // pointers from a loaded ClassMetadata. The Suite verifies the
        // structural fields agree across readers; live pointer values are
        // not embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnyClassMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnyClassMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
