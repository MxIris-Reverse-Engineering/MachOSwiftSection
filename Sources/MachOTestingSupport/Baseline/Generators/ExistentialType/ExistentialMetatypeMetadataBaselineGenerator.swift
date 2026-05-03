import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ExistentialMetatypeMetadataBaseline.swift`.
///
/// `ExistentialMetatypeMetadata` is the metadata for `(any P).Type` —
/// the metatype of an opaque/class-bound existential. Live carriers
/// require materialising the metatype value through Swift's runtime
/// (e.g. `(any P).self`), which is reachable only from a loaded process,
/// not from the static section walks. The fixture's existentials don't
/// emit a standalone `ExistentialMetatypeMetadata` record in the
/// `__swift5_types` family of sections, so we register only the
/// memberwise-synthesized init's surviving public members.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ExistentialMetatypeMetadataBaselineGenerator {
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
        // ExistentialMetatypeMetadata wraps a runtime metatype value
        // (`(any P).Type`); no live carrier is materialised from the
        // SymbolTestsCore section walks. The Suite asserts the type's
        // structural members behave correctly against a synthetic
        // memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialMetatypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialMetatypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
