import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/StructMetadataBaseline.swift`.
///
/// Unlike the descriptor-side baselines, this generator does NOT consume the
/// MachOFile fixture: `StructMetadata` instances can only be obtained by
/// invoking the metadata accessor function from a *loaded* MachOImage in the
/// current process. Encoding live pointer values in a literal would not be
/// stable across runs, so the Suite tests cover correctness via cross-reader
/// equality at runtime instead.
///
/// Consequently, the generated file only carries the registered member names
/// for the Coverage Invariant test (Task 16) to consult.
package enum StructMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in StructMetadata.swift.
        // `init(layout:offset:)` is filtered as memberwise synthesized.
        let registered = [
            "descriptorOffset",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // StructMetadata can only be materialized via MachOImage's accessor
        // function at runtime; live pointer values are not embedded here. The
        // companion Suite (StructMetadataTests) relies on cross-reader
        // equality between (MachOImage, fileContext, imageContext, inProcess)
        // for correctness.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StructMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
