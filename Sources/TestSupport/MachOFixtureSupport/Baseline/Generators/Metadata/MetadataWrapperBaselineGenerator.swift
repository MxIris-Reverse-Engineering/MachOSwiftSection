import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataWrapperBaseline.swift`.
///
/// `MetadataWrapper` is the `@CaseCheckable(.public)` /
/// `@AssociatedValue(.public)` enum dispatching across every metadata
/// kind. PublicMemberScanner sees only the source-declared members
/// (macro-injected case-presence helpers and associated-value extractors
/// are out of scope per `GenericRequirementContentBaseline`'s pattern):
///   - `anyMetadata`, `metadata` (computed properties)
///   - `valueWitnessTable` (3 overloads collapsing to one MethodKey)
///   - `resolve` (3 overloads collapsing to one MethodKey)
///
/// Live wrappers are materialised only via MachOImage's accessor
/// (`StructTest`'s `MetadataResponse.value.resolve(in:)`). The Suite asserts
/// the wrapper enum's `case` discriminant matches `.struct` and the
/// projected `metadata`/`anyMetadata` round-trip the offset.
package enum MetadataWrapperBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "anyMetadata",
            "metadata",
            "resolve",
            "valueWitnessTable",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // MetadataWrapper is materialised through MachOImage's accessor
        // (StructTest); the macro-injected case-presence helpers and
        // associated-value extractors are not visited by
        // PublicMemberScanner, so only the four source-declared members
        // appear in the registered set.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
