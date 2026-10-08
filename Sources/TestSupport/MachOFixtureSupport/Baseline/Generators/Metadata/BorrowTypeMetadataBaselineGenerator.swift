import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/BorrowTypeMetadataBaseline.swift`.
///
/// `BorrowTypeMetadata` is the runtime metadata kind for a `Builtin.Borrow<T>`
/// value (`MetadataKind.borrow = 0x309`, Swift 6.4 runtime). The runtime
/// allocates it lazily and no binary section carries one, so nothing in the
/// `SymbolTestsCore` fixture reaches a live instance. We emit only the
/// registered member names; the live path is exercised through
/// `RuntimeMetadataTypeBuilder.createBuiltinBorrowType` on a Swift 6.4
/// runtime.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum BorrowTypeMetadataBaselineGenerator {
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
        // Builtin.Borrow metadata is allocated lazily by the Swift 6.4 runtime
        // and never appears in a binary section, so no live instance is
        // reachable from the fixture. The Suite asserts the type's structural
        // members exist.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum BorrowTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("BorrowTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
