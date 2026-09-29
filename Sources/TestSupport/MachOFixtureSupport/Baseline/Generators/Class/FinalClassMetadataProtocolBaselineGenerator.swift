import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/FinalClassMetadataProtocolBaseline.swift`.
///
/// The protocol's `descriptor(...)` and `fieldOffsets(...)` overloads
/// require a live class metadata instance. Materialising one needs a
/// loaded MachOImage; consequently, the cross-reader assertions in the
/// Suite are asymmetric (the metadata originates from MachOImage but its
/// methods accept any `ReadingContext`).
package enum FinalClassMetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly across the
        // FinalClassMetadataProtocol extension blocks. Overload pairs
        // collapse to single MethodKey entries.
        let registered = [
            "descriptor",
            "fieldOffsets",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live ClassMetadata cannot be embedded as a literal; the Suite
        // verifies the methods produce cross-reader-consistent results
        // at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FinalClassMetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FinalClassMetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
