import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/CanonicalSpecializedMetadatasListEntryBaseline.swift`.
///
/// `CanonicalSpecializedMetadatasListEntry` is a trailing-objects payload
/// appended to descriptors that declare canonical metadata prespecializations.
/// The `SymbolTestsCore` fixture does NOT use any `@_specialize` / canonical-
/// metadata prespecialization directives, so no descriptor surfaces a
/// non-empty `canonicalSpecializedMetadatas` array.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum CanonicalSpecializedMetadatasListEntryBaselineGenerator {
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
        // SymbolTestsCore declares no canonical-metadata prespecializations,
        // so no live entry is materialised.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CanonicalSpecializedMetadatasListEntryBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CanonicalSpecializedMetadatasListEntryBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
