import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataBoundsBaseline.swift`.
///
/// `MetadataBounds` is the one-`(UInt32, UInt32)` payload describing a class
/// metadata's negative/positive prefix bounds. It is reachable through
/// `ClassMetadataBounds.layout.bounds` for any non-resilient Swift class.
/// Rather than materialise a class metadata (a MachOImage-only path), we
/// validate the structural fields via a constant round-trip — the Suite
/// asserts `MetadataBounds(layout:offset:)` preserves the supplied
/// `negativeSizeInWords`/`positiveSizeInWords`.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized; the
/// inherited `totalSizeInBytes`/`addressPointInBytes` are attributed to
/// `MetadataBoundsProtocol`.
package enum MetadataBoundsBaselineGenerator {
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
        // MetadataBounds is exercised via constant round-trip; live class-
        // metadata bounds are reachable only through MachOImage and are
        // covered by the ClassMetadataBoundsProtocol Suite.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataBoundsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            /// Constants used by the companion Suite to drive the round-trip.
            static let sampleNegativeSizeInWords: UInt32 = 0x2
            static let samplePositiveSizeInWords: UInt32 = 0x10
            static let sampleOffset: Int = 0x100
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataBoundsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
