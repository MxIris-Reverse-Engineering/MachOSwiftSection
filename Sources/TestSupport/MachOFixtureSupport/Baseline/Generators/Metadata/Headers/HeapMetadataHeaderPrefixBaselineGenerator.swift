import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/HeapMetadataHeaderPrefixBaseline.swift`.
///
/// `HeapMetadataHeaderPrefix` is the single-`destroy`-pointer slot
/// embedded in every heap metadata's three-word layout prefix
/// `(layoutString, destroy, valueWitnesses)`. Phase C5 converts this
/// suite to a real test that materialises the prefix at the second word
/// of `Classes.ClassTest`'s heap metadata layout (MachOImage-only path —
/// `MachOFile` cannot invoke runtime accessor functions). Live pointer
/// values are not embedded here because the runtime-installed `destroy`
/// callback is process-lifetime-stable but not reader-stable.
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
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: MachOImage path on `Classes.ClassTest`'s class metadata
        // (the prefix lives at `interop.offset - HeapMetadataHeader.layoutSize
        // + TypeMetadataLayoutPrefix.layoutSize`).
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
