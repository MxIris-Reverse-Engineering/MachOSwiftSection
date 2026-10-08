import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ValueMetadataBaseline.swift`.
///
/// `ValueMetadata` is the kind-erased value-type metadata wrapper (the
/// runtime layout shared by `StructMetadata` and `EnumMetadata`'s value
/// arms). Like its concrete-kind cousins, instances can only be obtained
/// by invoking the metadata accessor function from a *loaded* MachOImage
/// in the current process; live pointer values aren't stable across runs,
/// so we emit only the registered member names and let the companion
/// Suite verify cross-reader equality at runtime.
package enum ValueMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ValueMetadata.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ValueMetadata can only be materialized via a MachOImage accessor
        // function at runtime; live pointer values are not embedded here. The
        // companion Suite (ValueMetadataTests) relies on cross-reader
        // equality between the available reader axes for correctness.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ValueMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ValueMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
