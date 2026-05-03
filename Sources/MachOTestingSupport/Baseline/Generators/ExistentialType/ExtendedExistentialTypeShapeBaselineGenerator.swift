import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ExtendedExistentialTypeShapeBaseline.swift`.
///
/// `ExtendedExistentialTypeShape` is the trailing-objects layout that
/// describes a constrained existential's signature (the `any P<...>`
/// metadata's "shape"). It carries `existentialType` (a relative
/// pointer to the mangled existential type), a flags word, and a
/// requirement-signature header. SymbolTestsCore declares
/// primary-associated-type protocols, but the shape records are
/// emitted by the runtime on demand and are not directly indexed by
/// the static section walks. The Suite registers the type's public
/// surface and exercises the structural members against synthetic
/// instances; the `existentialType` accessor is exercised through a
/// presence-only smoke check on a synthetic carrier.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ExtendedExistentialTypeShapeBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in ExtendedExistentialTypeShape.swift.
        // The three `existentialType` overloads (MachO + InProcess +
        // ReadingContext) collapse to one MethodKey under the scanner's
        // name-only key. `ExtendedExistentialTypeShapeFlags` is covered
        // by its own baseline / Suite (declared in this same file).
        let registered = [
            "existentialType",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExtendedExistentialTypeShape is a runtime-allocated trailing-
        // objects payload; no live carrier is reachable from the
        // SymbolTestsCore section walks. The Suite asserts the type's
        // structural members behave correctly against a synthetic
        // memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeShapeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeShapeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
