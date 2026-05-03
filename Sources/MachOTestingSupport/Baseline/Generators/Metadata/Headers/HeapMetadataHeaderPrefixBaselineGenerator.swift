import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/HeapMetadataHeaderPrefixBaseline.swift`.
///
/// `HeapMetadataHeaderPrefix` is the single-`destroy`-pointer prefix
/// shared by every heap metadata layout. The Suite materialises the prefix
/// from a class metadata's full-metadata header (MachOImage-only path);
/// live pointer values are not embedded here.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum HeapMetadataHeaderPrefixBaselineGenerator {
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
        // HeapMetadataHeaderPrefix is materialised from MachOImage's
        // accessor; live pointer values aren't embedded.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum HeapMetadataHeaderPrefixBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("HeapMetadataHeaderPrefixBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
