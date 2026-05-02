import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MethodDefaultOverrideDescriptorBaseline.swift`.
///
/// `MethodDefaultOverrideDescriptor` represents a default implementation
/// override entry under `MethodDefaultOverrideTableHeader`. The
/// `SymbolTestsCore` fixture's classes don't emit a default-override
/// table, so we cannot pick a live instance. The baseline therefore
/// records only the registered member names; the companion Suite skips
/// the runtime portion with a documented note. Coverage of the live
/// behaviour will land when a fixture surfaces a default-override table
/// (Task 16 will track this via the allowlist if needed).
package enum MethodDefaultOverrideDescriptorBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in MethodDefaultOverrideDescriptor.swift.
        // Overload pairs collapse to single MethodKey entries via the scanner.
        let registered = [
            "implementationSymbols",
            "layout",
            "offset",
            "originalMethodDescriptor",
            "replacementMethodDescriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The SymbolTestsCore fixture does not declare any class with a
        // default-override table, so MethodDefaultOverrideDescriptor cannot
        // be sourced from the fixture. The Suite (MethodDefaultOverrideDescriptorTests)
        // exercises only static surface (Layout offsets) and documents the
        // missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodDefaultOverrideDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDefaultOverrideDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
