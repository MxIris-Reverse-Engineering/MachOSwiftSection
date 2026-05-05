import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ResilientWitnessesHeaderBaseline.swift`.
///
/// `ResilientWitnessesHeader` is the trailing-object header that announces
/// the resilient-witness array length (`numWitnesses`).
///
/// Picker: the first `ProtocolConformance` from the fixture with a
/// non-empty `resilientWitnesses` array (so the header materializes).
package enum ResilientWitnessesHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let conformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machO)
        let header = try required(conformance.resilientWitnessesHeader)

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in ResilientWitnessesHeader.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let headerComment = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: headerComment)

        enum ResilientWitnessesHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumWitnesses: UInt32
            }

            static let firstHeader = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ResilientWitnessesHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: ResilientWitnessesHeader) -> String {
        let offset = header.offset
        let numWitnesses = header.layout.numWitnesses

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumWitnesses: \(literal: numWitnesses)
        )
        """
        return expr.description
    }
}
