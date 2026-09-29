import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataBoundsBaseline.swift`.
///
/// `MetadataBounds` is the one-`(UInt32, UInt32)` payload describing a class
/// metadata's negative/positive prefix bounds. The Suite validates the
/// structural fields via a constant round-trip — `MetadataBounds(layout:offset:)`
/// preserves the supplied `negativeSizeInWords`/`positiveSizeInWords`.
///
/// Phase C5 considered conversion to a real test and kept sentinel — same
/// rationale as `ClassMetadataBounds`, which has no runtime derivation
/// path from a class metadata pointer (only static factories
/// `forSwiftRootClass`/`forAddressPointAndSize` and the `adjustForSubclass`
/// instance method).
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
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: bit-packing constants for MetadataBounds (no MachO fixture
        // is required; the Suite verifies the memberwise round-trip directly).
        // Phase C5 kept this Suite sentinel — see CoverageAllowlistEntries
        // for the rationale.
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
