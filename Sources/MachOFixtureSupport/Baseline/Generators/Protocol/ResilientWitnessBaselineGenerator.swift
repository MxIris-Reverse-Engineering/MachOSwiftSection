import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ResilientWitnessBaseline.swift`.
///
/// `ResilientWitness` describes a single requirement-implementation pair
/// stored in a protocol conformance's resilient witness table. Each
/// witness carries a `RelativeProtocolRequirementPointer` plus a relative
/// pointer to the implementation symbol.
///
/// Picker: the first `ProtocolConformance` from the fixture with a
/// non-empty `resilientWitnesses` array. We pin the resolved offset of
/// the first witness's `requirement(in:)` and the boolean presence of
/// `implementationSymbols(in:)`. `implementationAddress(in:)` is a
/// MachO-only debug formatter (see `ResilientWitness.swift` doc-comment)
/// — we register the name but do not assert on the live address string
/// (it's a base-16 representation of an in-memory pointer).
package enum ResilientWitnessBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let conformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machO)
        let firstWitness = try required(conformance.resilientWitnesses.first)

        let requirement = try firstWitness.requirement(in: machO)
        let hasRequirement = requirement != nil
        let hasImplementationSymbols = (try firstWitness.implementationSymbols(in: machO)) != nil
        let implementationOffset = firstWitness.implementationOffset

        let entryExpr = emitEntryExpr(
            offset: firstWitness.offset,
            hasRequirement: hasRequirement,
            hasImplementationSymbols: hasImplementationSymbols,
            implementationOffset: implementationOffset
        )

        // Public members declared directly in ResilientWitness.swift.
        // The `requirement(in:)` and `implementationSymbols(in:)` overloads
        // (MachO + InProcess + ReadingContext) collapse to single MethodKeys
        // under the scanner's name-based deduplication.
        // `implementationAddress(in:)` is a MachO-only debug formatter —
        // tracked here, exercised for type-correctness in the Suite.
        let registered = [
            "implementationAddress",
            "implementationOffset",
            "implementationSymbols",
            "layout",
            "offset",
            "requirement",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ResilientWitnessBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let hasRequirement: Bool
                let hasImplementationSymbols: Bool
                let implementationOffset: Int
            }

            static let firstWitness = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ResilientWitnessBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        offset: Int,
        hasRequirement: Bool,
        hasImplementationSymbols: Bool,
        implementationOffset: Int
    ) -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            hasRequirement: \(literal: hasRequirement),
            hasImplementationSymbols: \(literal: hasImplementationSymbols),
            implementationOffset: \(raw: BaselineEmitter.hex(implementationOffset))
        )
        """
        return expr.description
    }
}
