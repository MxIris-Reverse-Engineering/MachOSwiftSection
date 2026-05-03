import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/GenericValueHeaderBaseline.swift`.
///
/// `GenericValueHeader` is the trailing-object header announcing the
/// integer-value-parameter array on a generic context whose
/// `GenericContextDescriptorFlags.hasValues` bit is set. The
/// `SymbolTestsCore` fixture does NOT declare any integer-value generic
/// type, so a live header cannot be sourced. The baseline records only
/// the registered member names; the Suite documents the missing runtime
/// coverage.
package enum GenericValueHeaderBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in GenericValueHeader.swift.
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
        // The SymbolTestsCore fixture does not declare any integer-value
        // generic type, so a live GenericValueHeader cannot be sourced.
        // The Suite documents the missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericValueHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericValueHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
