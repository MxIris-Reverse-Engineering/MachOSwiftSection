import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/TupleTypeMetadataBaseline.swift`.
///
/// `TupleTypeMetadata` is the runtime metadata for tuple types. The
/// Swift runtime allocates these on demand when a tuple is used as a
/// type (field/parameter/return); there is no static record in
/// `__swift5_types` for the tuple itself. The Suite asserts the type's
/// structural members behave correctly against a synthetic memberwise
/// instance; the `elements(in:)` accessor short-circuits when
/// `numberOfElements == 0` so the early-out is safe to exercise on a
/// synthetic carrier.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
/// `Element` is a nested struct on `TupleTypeMetadata`; its public
/// stored properties (`type`, `offset`) are scanned under the
/// `Element` typeName. There's no separate `Element`/Layout file — the
/// scanner bins those keys under `Element` and they're tracked here so
/// the Coverage Invariant test sees them.
package enum TupleTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in TupleTypeMetadata.swift. The two
        // `elements` overloads (MachO + ReadingContext) collapse to one
        // MethodKey under the scanner's name-only key.
        let registered = [
            "elements",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // TupleTypeMetadata is allocated by the Swift runtime on demand;
        // no static record is reachable from SymbolTestsCore section
        // walks. The Suite asserts structural members behave correctly
        // against a synthetic memberwise instance and exercises the
        // zero-elements early-out of `elements(in:)`.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
