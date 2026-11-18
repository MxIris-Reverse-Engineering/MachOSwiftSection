import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataRequestBaseline.swift`.
///
/// `MetadataRequest` is a `MutableFlagSet` packing `state` (8 bits) and
/// `isBlocking` (1 bit) into a single `Int` raw value. The Suite drives the
/// type via constant round-trips through the three initialisers (no MachO
/// fixture is required) and asserts the bit-packing invariants. Phase C5
/// wraps the assertions in `usingInProcessOnly` so the suite is classified
/// as `.inProcessOnly` rather than `.sentinel` — the `InProcessContext` is
/// otherwise unused.
///
/// Public surface (after PublicMemberScanner name-only collapsing):
/// - `init(rawValue:)`, `init`, `init(state:isBlocking:)` — three distinct
///   keys (the parameter labels disambiguate them under
///   PublicMemberScanner).
/// - `completeAndBlocking` — static convenience constructor.
/// - `state`, `isBlocking`, `rawValue` — projected bitfield accessors
///   (rawValue inherited from `MutableFlagSet` but redeclared in body).
package enum MetadataRequestBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "completeAndBlocking",
            "init",
            "init(rawValue:)",
            "init(state:isBlocking:)",
            "isBlocking",
            "rawValue",
            "state",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: bit-packing constants for MetadataRequest's MutableFlagSet
        // (no MachO fixture is required; the Suite verifies invariants
        // directly under `usingInProcessOnly`).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataRequestBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            /// Constants used by the companion Suite to drive bit-packing
            /// round-trips.
            static let completeAndBlockingExpectedRawValue: Int = 0x100
            static let layoutCompleteRawValue: Int = 0x3F
            static let abstractRawValue: Int = 0xFF
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataRequestBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
