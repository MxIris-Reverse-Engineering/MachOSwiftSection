import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeLayoutBaseline.swift`.
///
/// `TypeLayout` is the (size, stride, flags, extraInhabitantCount)
/// quadruple projected from a `ValueWitnessTable`. It declares four
/// stored properties, a `dynamicMemberLookup` subscript that bridges
/// to `ValueWitnessFlags` keypaths, and `CustomStringConvertible` /
/// `CustomDebugStringConvertible` descriptions. The Suite re-evaluates
/// each accessor against synthetic instances; cross-reader equality is
/// covered by the live-carrier paths in the Metadata Suite.
package enum TypeLayoutBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in TypeLayout.swift.
        let registered = [
            "debugDescription",
            "description",
            "extraInhabitantCount",
            "flags",
            "size",
            "stride",
            "subscript(dynamicMember:)",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // TypeLayout is a pure value-type projection of (size, stride,
        // flags, extraInhabitantCount) from a ValueWitnessTable. The
        // Suite re-evaluates each accessor against a synthetic instance
        // — the underlying `flags` raw value is constructed from
        // ValueWitnessFlags' static `let isNonPOD` etc. constants so
        // the Suite is reader-independent.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeLayoutBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeLayoutBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
