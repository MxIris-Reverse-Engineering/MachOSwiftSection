import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/FullMetadataBaseline.swift`.
///
/// `FullMetadata<Metadata>` is the (`HeaderType.Layout`, `Metadata.Layout`)
/// pair preceded by the metadata pointer (the "full" metadata layout
/// includes the pre-header type-witness pointers). Live `FullMetadata`
/// instances are reachable only through MachOImage's metadata accessor (via
/// `MetadataProtocol.asFullMetadata`); the Suite (`FullMetadataTests`)
/// materialises a `FullMetadata<StructMetadata>` for `Structs.StructTest`
/// and asserts cross-reader equality between the (image, imageContext,
/// inProcess) reader axes.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum FullMetadataBaselineGenerator {
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
        // FullMetadata is materialised from a MachOImage metadata accessor
        // (via MetadataProtocol.asFullMetadata); live pointer values are not
        // embedded here. The companion Suite asserts cross-reader equality
        // between (MachOImage, imageContext, inProcess).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FullMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FullMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
