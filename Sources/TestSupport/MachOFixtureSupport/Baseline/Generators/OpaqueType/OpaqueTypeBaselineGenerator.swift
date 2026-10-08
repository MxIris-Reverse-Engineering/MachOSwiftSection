import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/OpaqueTypeBaseline.swift`.
///
/// `OpaqueType` is the high-level wrapper around `OpaqueTypeDescriptor`.
/// Beyond holding the descriptor it pre-resolves the optional
/// `genericContext`, the trailing `[MangledName]` underlying-type
/// arguments, and the optional `invertedProtocols` set.
///
/// The fixture's `OpaqueReturnTypes` declarations DO cause the compiler
/// to emit opaque type descriptors, but the SymbolTestsCore build
/// indexes them in a way that's not directly reachable from
/// `swift.contextDescriptors` nor from any context's parent chain on
/// the current toolchain. The Suite registers the type's public
/// surface and exercises members against a synthetic memberwise
/// instance.
///
/// Adding a fixture variant that surfaces an opaque type via a
/// reachable channel (e.g. a top-level `var x: some P` whose
/// underlying-type relationship can be walked back) would let the
/// Suite exercise the live carriers; the present fixture does not.
package enum OpaqueTypeBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in OpaqueType.swift.
        let registered = [
            "descriptor",
            "genericContext",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "invertedProtocols",
            "underlyingTypeArgumentMangledNames",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // OpaqueType wraps an OpaqueTypeDescriptor; SymbolTestsCore's
        // opaque-type descriptors aren't directly reachable from
        // swift.contextDescriptors or via parent chains on the current
        // toolchain. The Suite registers the public surface and
        // exercises members against a synthetic memberwise instance.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum OpaqueTypeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("OpaqueTypeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
