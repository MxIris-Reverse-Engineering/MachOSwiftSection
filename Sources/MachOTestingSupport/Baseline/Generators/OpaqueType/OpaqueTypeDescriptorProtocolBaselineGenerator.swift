import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/OpaqueTypeDescriptorProtocolBaseline.swift`.
///
/// `OpaqueTypeDescriptorProtocol` extends every conforming type
/// (currently only `OpaqueTypeDescriptor`) with the
/// `numUnderlyingTypeArugments` accessor — the kind-specific flags
/// raw value cast to `Int`. SymbolTestsCore's opaque-type descriptors
/// aren't directly reachable on the current toolchain (see
/// OpaqueTypeBaseline), so the Suite exercises the accessor against a
/// synthetic memberwise `OpaqueTypeDescriptor`.
package enum OpaqueTypeDescriptorProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "numUnderlyingTypeArugments",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // OpaqueTypeDescriptorProtocol — see OpaqueTypeBaseline for the
        // discoverability caveat. The Suite exercises the
        // numUnderlyingTypeArugments accessor against a synthetic
        // memberwise OpaqueTypeDescriptor whose
        // ContextDescriptorFlags' kind-specific bits encode a known
        // count.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum OpaqueTypeDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("OpaqueTypeDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
