import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/FixedArrayTypeMetadataBaseline.swift`.
///
/// `FixedArrayTypeMetadata` is the runtime metadata kind for the experimental
/// `FixedArray<N, T>` Swift built-in (`MetadataKind.fixedArray = 0x308`). The
/// `SymbolTestsCore` fixture does not declare any such types, so no live
/// instance can be reached through the static section walks. We emit only
/// the registered member names; the structural members are exercised
/// indirectly via `MetadataWrapper.fixedArray(_:)` once a fixed-array fixture
/// is added.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum FixedArrayTypeMetadataBaselineGenerator {
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
        // SymbolTestsCore declares no FixedArray types, so no live metadata
        // is reachable. The Suite asserts the type's structural members
        // exist; runtime payloads will be exercised when a fixed-array
        // fixture is added.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FixedArrayTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FixedArrayTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
