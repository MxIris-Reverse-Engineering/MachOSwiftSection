import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/CanonicalSpecializedMetadatasListCountBaseline.swift`.
///
/// `CanonicalSpecializedMetadatasListCount` is a one-`UInt32` raw-representable
/// wrapper; the count is read from the trailing-objects payload of descriptors
/// with the `hasCanonicalMetadataPrespecializations` bit. The `SymbolTestsCore`
/// fixture declares no prespecializations, so no live count is materialised.
///
/// The Suite covers the round-trip through `init(rawValue:)` / `rawValue` to
/// witness the macro-style constructor of a raw-representable type.
package enum CanonicalSpecializedMetadatasListCountBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // RawRepresentable wrapper around a UInt32 count; SymbolTestsCore
        // declares no canonical-metadata prespecializations, so the value is
        // exercised via constant round-trip rather than by reading the
        // fixture.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CanonicalSpecializedMetadatasListCountBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            /// Constant round-trip witness used by the companion Suite.
            static let sampleRawValue: UInt32 = 0x2A
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CanonicalSpecializedMetadatasListCountBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
