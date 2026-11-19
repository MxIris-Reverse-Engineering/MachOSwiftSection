import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MethodDefaultOverrideTableHeaderBaseline.swift`.
///
/// `MethodDefaultOverrideTableHeader` is the trailing-object header for the
/// default-override table. The `SymbolTestsCore` fixture's classes don't
/// declare a default-override table, so we cannot pick a live instance.
/// The baseline therefore records only the registered member names; the
/// Suite (`MethodDefaultOverrideTableHeaderTests`) skips the runtime
/// portion with a documented note.
package enum MethodDefaultOverrideTableHeaderBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in MethodDefaultOverrideTableHeader.swift.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The SymbolTestsCore fixture does not declare any class with a
        // default-override table, so MethodDefaultOverrideTableHeader cannot
        // be sourced. The Suite documents the missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodDefaultOverrideTableHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDefaultOverrideTableHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
