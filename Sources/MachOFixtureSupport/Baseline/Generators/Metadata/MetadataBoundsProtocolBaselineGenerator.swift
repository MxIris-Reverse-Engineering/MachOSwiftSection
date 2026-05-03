import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataBoundsProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `totalSizeInBytes` and `addressPointInBytes` are declared in
/// `extension MetadataBoundsProtocol { ... }` and attribute to the
/// protocol, not to concrete bounds carriers like `MetadataBounds`.
///
/// The Suite uses a constant `MetadataBounds` round-trip to assert the
/// derived sizes match the closed-form formula
/// `(neg + pos) * sizeof(StoredPointer)` and
/// `neg * sizeof(StoredPointer)` respectively.
package enum MetadataBoundsProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "addressPointInBytes",
            "totalSizeInBytes",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The derived sizes are computed from the closed-form formulas
        //   totalSizeInBytes    = (neg + pos) * sizeof(StoredPointer)
        //   addressPointInBytes =  neg        * sizeof(StoredPointer)
        // The Suite drives a constant MetadataBounds(neg=2, pos=16) and
        // checks both expressions.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataBoundsProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            /// Constants matching `MetadataBoundsBaseline` so the Suites
            /// stay aligned without cross-baseline references.
            static let sampleNegativeSizeInWords: UInt32 = 0x2
            static let samplePositiveSizeInWords: UInt32 = 0x10
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataBoundsProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
