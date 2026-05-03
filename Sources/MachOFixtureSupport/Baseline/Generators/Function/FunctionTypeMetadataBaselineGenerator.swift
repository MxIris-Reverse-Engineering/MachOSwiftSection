import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/FunctionTypeMetadataBaseline.swift`.
///
/// `FunctionTypeMetadata` is the runtime metadata for function types
/// (`(Int) -> Bool`, `() async throws -> ()`, etc.). The Swift runtime
/// allocates these on demand; no static record is reachable from the
/// SymbolTestsCore section walks. The Suite asserts the type's
/// structural members behave correctly against a synthetic memberwise
/// instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum FunctionTypeMetadataBaselineGenerator {
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
        // FunctionTypeMetadata is allocated by the Swift runtime on
        // demand; no static carrier is reachable from SymbolTestsCore.
        // The Suite asserts structural members behave against a
        // synthetic memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
