import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/TupleTypeMetadataElementBaseline.swift`.
///
/// `TupleTypeMetadata.Element` is the nested struct describing a single
/// tuple element entry — a `(type: ConstMetadataPointer<Metadata>,
/// offset: StoredSize)` pair. `PublicMemberScanner` keys nested types
/// by their inner struct name (`Element`), so the Suite registers under
/// `testedTypeName == "Element"` and the baseline tracks the two
/// stored properties.
///
/// `TupleTypeMetadata.Element` is conceptually a layout fixture (no
/// methods, just stored ivars), so the baseline is round-trippable
/// against synthetic raw values.
package enum TupleTypeMetadataElementBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared on TupleTypeMetadata.Element.
        let registered = [
            "offset",
            "type",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // TupleTypeMetadata.Element is a nested struct describing one
        // tuple element. It declares two public stored properties and
        // no methods. The Suite round-trips the property values via a
        // synthetic memberwise instance.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataElementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let typeAddress: UInt64 = 0x1234_5000
            static let elementOffset: UInt64 = 0x10
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataElementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
