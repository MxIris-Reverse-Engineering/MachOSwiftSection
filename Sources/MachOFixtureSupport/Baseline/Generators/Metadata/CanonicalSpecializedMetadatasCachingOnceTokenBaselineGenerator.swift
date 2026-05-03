import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/CanonicalSpecializedMetadatasCachingOnceTokenBaseline.swift`.
///
/// `CanonicalSpecializedMetadatasCachingOnceToken` is appended to descriptors
/// with the `hasCanonicalMetadataPrespecializations` bit, between the
/// metadata accessors list and the trailing data. The `SymbolTestsCore`
/// fixture declares no prespecializations, so no live token is materialised.
/// We emit only the registered member names.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum CanonicalSpecializedMetadatasCachingOnceTokenBaselineGenerator {
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
        // so no live token is materialised. The Suite asserts the type's
        // structural members exist.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CanonicalSpecializedMetadatasCachingOnceTokenBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CanonicalSpecializedMetadatasCachingOnceTokenBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
