import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AnonymousContextDescriptorProtocolBaseline.swift`.
///
/// The protocol's three `mangledName(in:)` overloads (MachO / InProcess /
/// ReadingContext) plus the `hasMangledName` derived var don't have stable
/// literal payloads (the `MangledName` parse output is a deep tree). The
/// companion Suite (AnonymousContextDescriptorProtocolTests) verifies the
/// methods produce cross-reader-consistent results at runtime against the
/// presence flag recorded here.
///
/// The presence flag is sourced from the same picker as the Flags Suite
/// (`anonymous_first`), so the two Suites move together — but having the
/// flag mirrored on this Suite's own baseline keeps the assertions
/// self-contained.
package enum AnonymousContextDescriptorProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.anonymous_first(in: machO)
        let hasMangledName = descriptor.hasMangledName
        let entryExpr = emitEntryExpr(hasMangledName: hasMangledName)

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

            struct Entry {
                let hasMangledName: Bool
            }

            static let firstAnonymous = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AnonymousContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(hasMangledName: Bool) -> String {
        let expr: ExprSyntax = """
        Entry(
            hasMangledName: \(literal: hasMangledName)
        )
        """
        return expr.description
    }
}
