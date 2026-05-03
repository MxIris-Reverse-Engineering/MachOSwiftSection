import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ExistentialTypeMetadataBaseline.swift`.
///
/// `ExistentialTypeMetadata` is the runtime metadata for `any P` /
/// `any P & Q` opaque or class-bound existentials. The metadata is
/// allocated by the runtime when a type uses an existential (e.g. as a
/// field, parameter, return), and there's no static record in
/// `__swift5_types` for the existential itself — only for the
/// containing types. The Suite asserts the type's structural members
/// behave correctly against a synthetic memberwise instance; the
/// `superclassConstraint` / `protocols` accessors are exercised against
/// a flag layout that yields empty results.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ExistentialTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in ExistentialTypeMetadata.swift.
        // The three `superclassConstraint` overloads collapse to one
        // MethodKey under PublicMemberScanner's name-only key, as do
        // the three `protocols` overloads.
        let registered = [
            "isClassBounded",
            "isObjC",
            "layout",
            "offset",
            "protocols",
            "representation",
            "superclassConstraint",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExistentialTypeMetadata is allocated by the Swift runtime on
        // demand; no static record is reachable from SymbolTestsCore
        // section walks. The Suite asserts structural members behave
        // correctly against synthetic memberwise instances spanning
        // the documented kind/representation arms.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
