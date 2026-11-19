import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ForeignMetadataInitializationBaseline.swift`.
///
/// `ForeignMetadataInitialization` is a single-`completionFunction`-pointer
/// trailing-objects payload appended to descriptors with the
/// `hasForeignMetadataInitialization` bit. The bit fires for foreign-class
/// metadata bridging (e.g. `@_objcRuntimeName` / Core Foundation classes
/// imported into Swift). The `SymbolTestsCore` fixture does not declare any
/// such types, so no live entry is materialised.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ForeignMetadataInitializationBaselineGenerator {
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
        // SymbolTestsCore declares no foreign-class types, so no live
        // ForeignMetadataInitialization entry is materialised. The Suite
        // asserts the type's structural members exist.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ForeignMetadataInitializationBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ForeignMetadataInitializationBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
