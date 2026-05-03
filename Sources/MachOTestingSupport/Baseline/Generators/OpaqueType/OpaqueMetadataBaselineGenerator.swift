import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/OpaqueMetadataBaseline.swift`.
///
/// `OpaqueMetadata` is a single-`kind`-field metadata for opaque
/// types built into the Swift runtime (e.g. `Builtin.RawPointer`'s
/// metadata). It is materialised by the runtime; no static record is
/// reachable from SymbolTestsCore section walks.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum OpaqueMetadataBaselineGenerator {
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
        // OpaqueMetadata wraps a runtime-only opaque-type metadata
        // header; no static carrier is reachable from SymbolTestsCore.
        // The Suite asserts structural members against a synthetic
        // memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum OpaqueMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("OpaqueMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
