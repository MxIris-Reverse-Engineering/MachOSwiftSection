import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/OpaqueTypeDescriptorBaseline.swift`.
///
/// `OpaqueTypeDescriptor` is the section-stored opaque type descriptor
/// emitted by the compiler for each `some P` opaque return type.
/// SymbolTestsCore's opaque-type descriptors aren't directly reachable
/// from `swift.contextDescriptors` or via parent chains on the current
/// toolchain — see the OpaqueType Suite for the same caveat. The Suite
/// here registers the public surface and exercises members against a
/// synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum OpaqueTypeDescriptorBaselineGenerator {
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
        // OpaqueTypeDescriptor — see OpaqueTypeBaseline for the
        // discoverability caveat. Synthetic memberwise instance only.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum OpaqueTypeDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("OpaqueTypeDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
