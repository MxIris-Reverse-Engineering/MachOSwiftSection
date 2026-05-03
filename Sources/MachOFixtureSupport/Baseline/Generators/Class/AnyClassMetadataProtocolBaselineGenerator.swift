import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/AnyClassMetadataProtocolBaseline.swift`.
///
/// The protocol's `asFinalClassMetadata(...)` overloads (MachO + InProcess
/// + ReadingContext) require a live class metadata instance reachable
/// only from a loaded MachOImage. This baseline records only the
/// registered member names; the Suite asserts cross-reader agreement at
/// runtime.
package enum AnyClassMetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in AnyClassMetadataProtocol.swift.
        // The three `asFinalClassMetadata(...)` overloads collapse to a
        // single MethodKey under PublicMemberScanner.
        let registered = [
            "asFinalClassMetadata",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live AnyClassMetadata cannot be embedded as a literal; the
        // companion Suite (AnyClassMetadataProtocolTests) verifies the
        // method produces cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnyClassMetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnyClassMetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
