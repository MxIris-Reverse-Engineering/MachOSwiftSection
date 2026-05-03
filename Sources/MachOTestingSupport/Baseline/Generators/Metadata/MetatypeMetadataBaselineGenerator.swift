import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetatypeMetadataBaseline.swift`.
///
/// `MetatypeMetadata` (kind `0x304`) is the runtime metadata for `T.Type`
/// metatype values. It is materialised by the runtime when reflection asks
/// for the metadata of a metatype expression; static section walks of a
/// MachO never surface a live instance. We emit only the registered member
/// names; the cross-reader equality block on the structural members is
/// covered transitively by `MetadataWrapper.metatype(_:)`.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum MetatypeMetadataBaselineGenerator {
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
        // MetatypeMetadata is a runtime-only metadata kind (kind 0x304); no
        // section walk surfaces a live instance. The Suite asserts the type's
        // structural members exist.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetatypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetatypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
