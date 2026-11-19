import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataBaseline.swift`.
///
/// `Metadata` is the kind-erased one-pointer header shared by every
/// `MetadataKind`; its only stored field is `kind: StoredPointer`. Because
/// the `kind` value of a Swift class metadata is the descriptor pointer (not
/// a runtime kind tag), live `Metadata.layout.kind` values are not stable
/// across runs. The Suite (`MetadataTests`) materialises a value-type
/// `Metadata` (StructTest) — whose `kind` IS a stable scalar — and asserts
/// the cross-reader equality block at runtime.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum MetadataBaselineGenerator {
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
        // Metadata is materialised through MachOImage's metadata accessor at
        // runtime (the Suite uses StructTest as a stable value-type witness).
        // Live pointer values aren't embedded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
