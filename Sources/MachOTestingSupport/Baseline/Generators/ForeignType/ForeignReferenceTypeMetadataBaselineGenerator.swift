import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ForeignReferenceTypeMetadataBaseline.swift`.
///
/// `ForeignReferenceTypeMetadata` is the metadata for the Swift 5.7
/// "foreign reference type" import — C++ types annotated with
/// `SWIFT_SHARED_REFERENCE`. SymbolTestsCore has no such imports, so
/// no live carrier is reachable. The Suite asserts structural members
/// behave correctly against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ForeignReferenceTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "classDescriptor",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ForeignReferenceTypeMetadata describes the Swift 5.7 "foreign
        // reference type" import (C++ types with SWIFT_SHARED_REFERENCE).
        // SymbolTestsCore has no such imports, so no live carrier is
        // reachable. The Suite asserts structural members behave against
        // a synthetic memberwise instance.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ForeignReferenceTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ForeignReferenceTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
