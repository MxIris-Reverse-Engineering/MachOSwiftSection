import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ForeignClassMetadataBaseline.swift`.
///
/// `ForeignClassMetadata` is the metadata for foreign-class types — Swift
/// representations of Core Foundation classes (`CFString`, `CFArray`, etc.)
/// imported via `_objcRuntimeName` bridging. The fixture has no foreign
/// CF/ObjC class bridging, so no live carrier is reachable from the
/// SymbolTestsCore section walks. The Suite asserts structural members
/// behave correctly against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ForeignClassMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in ForeignClassMetadata.swift. The
        // three `classDescriptor` overloads (MachO + InProcess +
        // ReadingContext) collapse to one MethodKey under the scanner's
        // name-only key.
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
        // ForeignClassMetadata describes Swift representations of CF/ObjC
        // foreign classes. SymbolTestsCore declares no such bridges, so
        // no live carrier is reachable. The Suite asserts structural
        // members behave correctly against a synthetic memberwise
        // instance. Adding a `_objcRuntimeName`-bearing class to the
        // fixture would let the Suite exercise `classDescriptor(in:)` on
        // a real carrier.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ForeignClassMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ForeignClassMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
