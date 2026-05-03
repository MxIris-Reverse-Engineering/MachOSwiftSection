import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/SingletonMetadataPointerBaseline.swift`.
///
/// `SingletonMetadataPointer` is a trailing-objects payload appended to
/// descriptors with the `hasSingletonMetadataPointer` bit. The
/// `SymbolTestsCore` fixture has no descriptor that surfaces this bit (it
/// fires for cross-module canonical metadata caching, which the fixture
/// doesn't use), so no live entry is materialised. We emit only the
/// registered member names.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum SingletonMetadataPointerBaselineGenerator {
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
        // SymbolTestsCore declares no descriptors carrying a singleton-
        // metadata-pointer trailing object, so no live entry is materialised.
        // The Suite asserts the type's structural members exist.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum SingletonMetadataPointerBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("SingletonMetadataPointerBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
