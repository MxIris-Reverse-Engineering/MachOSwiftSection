import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/NonUniqueExtendedExistentialTypeShapeBaseline.swift`.
///
/// `NonUniqueExtendedExistentialTypeShape` is the non-unique variant of
/// `ExtendedExistentialTypeShape`, emitted statically by the compiler
/// before runtime deduplication. Once the runtime uniques shapes,
/// `ExtendedExistentialTypeMetadata.shape` always points at the unique
/// form — so the non-unique form is not reachable through
/// `InProcessMetadataPicker`. `SymbolTestsCore` doesn't currently emit a
/// non-unique shape statically either. The Suite stays sentinel and
/// asserts structural members behave correctly against a synthetic
/// memberwise instance.
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
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: sentinel — non-unique shape only reachable from compiler-emitted
        // static records before runtime dedup; runtime metadata always points at
        // the unique form. SymbolTestsCore doesn't currently emit one statically.
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
