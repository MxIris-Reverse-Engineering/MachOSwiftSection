import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/ExtendedExistentialTypeShapeFlagsBaseline.swift`.
///
/// `ExtendedExistentialTypeShapeFlags` is a 32-bit `OptionSet` declared
/// alongside `ExtendedExistentialTypeShape` in the same source file. It
/// declares only `init(rawValue:)` and `rawValue` — no semantic accessors
/// are exposed in the current source. The Suite round-trips raw values
/// through the OptionSet membership API to catch any accidental
/// public-surface changes.
package enum ExtendedExistentialTypeShapeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "init(rawValue:)",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ExtendedExistentialTypeShapeFlags currently exposes only
        // OptionSet boilerplate (init(rawValue:) + rawValue). The Suite
        // round-trips a small set of raw values to catch surface drift.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExtendedExistentialTypeShapeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let rawValues: [UInt32] = [0x0, 0x1, 0x2, 0xFF, 0xFFFF_FFFF]
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExtendedExistentialTypeShapeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
