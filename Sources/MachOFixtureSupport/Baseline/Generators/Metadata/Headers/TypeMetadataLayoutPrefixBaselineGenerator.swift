import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/TypeMetadataLayoutPrefixBaseline.swift`.
///
/// `TypeMetadataLayoutPrefix` is the single-`layoutString`-pointer prefix
/// preceding every type metadata header. Live header instances are
/// materialised through MachOImage's accessor; live pointer values are not
/// embedded.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum TypeMetadataLayoutPrefixBaselineGenerator {
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
        // TypeMetadataLayoutPrefix is materialised from MachOImage's
        // accessor; live pointer values aren't embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeMetadataLayoutPrefixBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeMetadataLayoutPrefixBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
