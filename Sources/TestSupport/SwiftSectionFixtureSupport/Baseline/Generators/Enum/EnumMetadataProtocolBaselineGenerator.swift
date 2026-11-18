import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/EnumMetadataProtocolBaseline.swift`.
///
/// Like `StructMetadataProtocolBaselineGenerator`, this only emits the
/// registered member names. The protocol's `enumDescriptor`/`payloadSize`
/// methods all require a live `EnumMetadata` instance, which is only
/// reachable through MachOImage at runtime. Cross-reader equality
/// assertions in the companion Suite (EnumMetadataProtocolTests) cover
/// correctness.
package enum EnumMetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in EnumMetadataProtocol.swift.
        // Both `enumDescriptor` and `payloadSize` have multiple overloads
        // (MachO/InProcess/ReadingContext) — they collapse to single
        // MethodKey entries via PublicMemberScanner's name-only key.
        let registered = [
            "enumDescriptor",
            "payloadSize",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live EnumMetadata pointers cannot be embedded as literals; the
        // companion Suite (EnumMetadataProtocolTests) verifies the methods
        // produce cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum EnumMetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("EnumMetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
