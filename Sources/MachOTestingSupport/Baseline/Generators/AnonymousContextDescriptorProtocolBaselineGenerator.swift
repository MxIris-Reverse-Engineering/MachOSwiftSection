import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/AnonymousContextDescriptorProtocolBaseline.swift`.
///
/// The protocol's three `mangledName(in:)` overloads (MachO / InProcess /
/// ReadingContext) plus the `hasMangledName` derived var don't have stable
/// literal payloads (the `MangledName` parse output is a deep tree). The
/// companion Suite (AnonymousContextDescriptorProtocolTests) verifies the
/// methods produce cross-reader-consistent results at runtime.
///
/// Consequently, the generated file only carries the registered member
/// names for the Coverage Invariant test (Task 16) to consult.
package enum AnonymousContextDescriptorProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared directly in AnonymousContextDescriptorProtocol.swift.
        // The three `mangledName(in:)` overloads collapse to a single
        // MethodKey via PublicMemberScanner's name-only key.
        let registered = [
            "hasMangledName",
            "mangledName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // MangledName payloads aren't embedded as literals; the companion
        // Suite (AnonymousContextDescriptorProtocolTests) verifies the
        // methods produce cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AnonymousContextDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnonymousContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
