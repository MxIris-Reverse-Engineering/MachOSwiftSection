import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ClassMetadataBaseline.swift`.
///
/// Like `StructMetadataBaselineGenerator`, this generator does NOT consume
/// the MachOFile fixture: `ClassMetadata` instances can only be obtained
/// by invoking the class's metadata accessor function from a *loaded*
/// MachOImage in the current process. Encoding live pointer values in a
/// literal would not be stable across runs, so the Suite tests cover
/// correctness via cross-reader equality at runtime instead.
package enum ClassMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ClassMetadata.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
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
        // ClassMetadata can only be materialized via MachOImage's accessor
        // function at runtime; live pointer values are not embedded here.
        // The companion Suite (ClassMetadataTests) relies on cross-reader
        // equality between (MachOImage, fileContext, imageContext,
        // inProcess) for correctness.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
