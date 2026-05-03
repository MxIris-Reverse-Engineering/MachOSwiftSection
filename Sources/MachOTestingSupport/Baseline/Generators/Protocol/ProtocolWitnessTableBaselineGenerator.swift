import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolWitnessTableBaseline.swift`.
///
/// `ProtocolWitnessTable` is a thin trailing-object wrapper exposing a
/// pointer to the `ProtocolConformanceDescriptor` that owns the table.
/// It carries no derived accessors of its own — the public API is just
/// the layout-wrapper trio (`offset`, `layout`, `init(layout:offset:)`).
///
/// We pick a live witness-table pattern from the first `ProtocolConformance`
/// in the fixture that surfaces one (most conformances do), and record
/// the offset.
package enum ProtocolWitnessTableBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let conformance = try required(
            try machO.swift.protocolConformances.first(where: { $0.witnessTablePattern != nil })
        )
        let witnessTable = try required(conformance.witnessTablePattern)
        let entryExpr = emitEntryExpr(for: witnessTable)

        // Public members declared directly in ProtocolWitnessTable.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolWitnessTableBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
            }

            static let firstWitnessTable = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolWitnessTableBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for witnessTable: ProtocolWitnessTable) -> String {
        let offset = witnessTable.offset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset))
        )
        """
        return expr.description
    }
}
