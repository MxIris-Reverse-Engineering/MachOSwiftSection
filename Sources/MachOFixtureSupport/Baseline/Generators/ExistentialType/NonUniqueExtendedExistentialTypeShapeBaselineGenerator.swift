import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/NonUniqueExtendedExistentialTypeShapeBaseline.swift`.
///
/// `NonUniqueExtendedExistentialTypeShape` is the non-unique variant of
/// `ExtendedExistentialTypeShape`, used by the runtime to cache shapes
/// per-image before deduplication. It carries a `uniqueCache` relative
/// pointer plus an embedded `localCopy` of the shape layout. As with
/// `ExtendedExistentialTypeShape`, no live carrier is reachable from
/// the SymbolTestsCore section walks; the Suite registers the type's
/// public surface and exercises members against synthetic instances.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum NonUniqueExtendedExistentialTypeShapeBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in
        // NonUniqueExtendedExistentialTypeShape.swift. The three
        // `existentialType` overloads collapse to one MethodKey under
        // PublicMemberScanner's name-only key.
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
        // NonUniqueExtendedExistentialTypeShape is a runtime-allocated
        // payload; no live carrier is reachable from SymbolTestsCore
        // section walks. The Suite asserts structural members behave
        // correctly against a synthetic memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum NonUniqueExtendedExistentialTypeShapeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("NonUniqueExtendedExistentialTypeShapeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
