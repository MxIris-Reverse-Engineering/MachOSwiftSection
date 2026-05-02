import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/StructMetadataProtocolBaseline.swift`.
///
/// Like `StructMetadataBaselineGenerator`, this only emits the registered
/// member names. The protocol's `structDescriptor`/`fieldOffsets` family of
/// methods all require a live `StructMetadata` instance, which is only
/// reachable through MachOImage at runtime. Cross-reader equality assertions
/// in the companion Suite (StructMetadataProtocolTests) cover correctness.
package enum StructMetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in StructMetadataProtocol.swift.
        // Both `structDescriptor` and `fieldOffsets` have multiple overloads
        // (MachO/InProcess/ReadingContext) — they collapse to single
        // MethodKey entries via PublicMemberScanner's name-only key.
        let registered = [
            "fieldOffsets",
            "structDescriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift run baseline-generator
        // Source fixture: SymbolTestsCore.framework
        //
        // Live StructMetadata pointers cannot be embedded as literals; the
        // companion Suite (StructMetadataProtocolTests) verifies the methods
        // produce cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructMetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StructMetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
