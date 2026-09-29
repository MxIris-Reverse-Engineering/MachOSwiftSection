import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ValueMetadataProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `descriptor` is declared in `extension ValueMetadataProtocol { ... }`
/// (across body, in-process, and ReadingContext variants) and attributes
/// to the protocol. The three overloads collapse to one MethodKey under
/// PublicMemberScanner's name-only key.
///
/// Like `StructMetadataProtocolBaseline`, this only emits the registered
/// member name. The protocol's `descriptor` method requires a live
/// `ValueMetadata`-conforming instance, only reachable through MachOImage
/// at runtime. Cross-reader equality assertions in the companion Suite
/// (ValueMetadataProtocolTests) cover correctness.
package enum ValueMetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "descriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live ValueMetadata pointers cannot be embedded as literals; the
        // companion Suite (ValueMetadataProtocolTests) verifies the method
        // produces cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ValueMetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ValueMetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
