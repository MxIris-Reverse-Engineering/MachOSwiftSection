import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/GenericValueDescriptorBaseline.swift`.
///
/// `GenericValueDescriptor` is the per-value record for integer-value
/// generic parameters (e.g. `struct Buffer<let N: Int>`). The
/// `SymbolTestsCore` fixture does NOT declare any integer-value generic
/// type, so we cannot pick a live descriptor. The baseline records only
/// the registered member names; the Suite documents the missing runtime
/// coverage.
package enum GenericValueDescriptorBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in GenericValueDescriptor.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
            "type",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The SymbolTestsCore fixture does not declare any integer-value
        // generic type (e.g. `struct Buffer<let N: Int>`), so a live
        // GenericValueDescriptor cannot be sourced. The Suite documents
        // the missing runtime coverage.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericValueDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericValueDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
