import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolConformanceBaseline.swift`.
///
/// `ProtocolConformance` is the high-level wrapper around
/// `ProtocolConformanceDescriptor`. The init eagerly materializes the
/// descriptor's protocol/typeReference/witnessTablePattern plus the
/// trailing-objects payload (retroactiveContextDescriptor / conditional
/// requirements / pack shape descriptors / resilient witnesses /
/// generic witness table / global actor reference) gated on the flag bits
/// of `ProtocolConformanceFlags`.
///
/// Three pickers feed the baseline so each trailing-object branch is
/// witnessed by at least one entry:
///   - `Structs.StructTest: Protocols.ProtocolTest` — the simplest path:
///     non-retroactive, no global-actor isolation, no resilient witnesses,
///     no conditional requirements. Surfaces the empty-trailing-objects
///     baseline for the `protocol` / `typeReference` / `witnessTablePattern`
///     stored properties.
///   - The first conditional conformance from
///     `ConditionalConformanceVariants.ConditionalContainerTest` — surfaces
///     the `conditionalRequirements` array (and `numConditionalRequirements`
///     flag bits) with a non-zero count.
///   - The first global-actor-isolated conformance from `Actors`
///     (`Actors.GlobalActorIsolatedConformanceTest: @MainActor ...` etc.) —
///     surfaces the `globalActorReference` trailing object.
///   - The first conformance with resilient witnesses (reused from Task 10's
///     `protocolConformance_resilientWitnessFirst`) — surfaces
///     `resilientWitnessesHeader` and a non-empty `resilientWitnesses`
///     array.
package enum ProtocolConformanceBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machO)
        let conditional = try BaselineFixturePicker.protocolConformance_conditionalFirst(in: machO)
        let globalActor = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machO)
        let resilient = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machO)

        let structTestExpr = emitEntryExpr(for: structTest)
        let conditionalExpr = emitEntryExpr(for: conditional)
        let globalActorExpr = emitEntryExpr(for: globalActor)
        let resilientExpr = emitEntryExpr(for: resilient)

        // Public members declared directly in ProtocolConformance.swift
        // (across the body and the same-file ReadingContext extension).
        // The `init(descriptor:in:)` MachO and ReadingContext overloads
        // collapse to a single MethodKey under PublicMemberScanner's
        // name-based deduplication. `flags` is a derived computed
        // property over `descriptor.flags`.
        let registered = [
            "conditionalPackShapeDescriptors",
            "conditionalRequirements",
            "descriptor",
            "flags",
            "genericWitnessTable",
            "globalActorReference",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "protocol",
            "resilientWitnesses",
            "resilientWitnessesHeader",
            "retroactiveContextDescriptor",
            "typeReference",
            "witnessTablePattern",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolConformanceBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let flagsRawValue: UInt32
                let hasProtocol: Bool
                let hasWitnessTablePattern: Bool
                let hasRetroactiveContextDescriptor: Bool
                let conditionalRequirementsCount: Int
                let conditionalPackShapeDescriptorsCount: Int
                let hasResilientWitnessesHeader: Bool
                let resilientWitnessesCount: Int
                let hasGenericWitnessTable: Bool
                let hasGlobalActorReference: Bool
            }

            static let structTestProtocolTest = \(raw: structTestExpr)

            static let conditionalFirst = \(raw: conditionalExpr)

            static let globalActorFirst = \(raw: globalActorExpr)

            static let resilientFirst = \(raw: resilientExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolConformanceBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for conformance: ProtocolConformance) -> String {
        let descriptorOffset = conformance.descriptor.offset
        let flagsRawValue = conformance.flags.rawValue
        let hasProtocol = conformance.protocol != nil
        let hasWitnessTablePattern = conformance.witnessTablePattern != nil
        let hasRetroactiveContextDescriptor = conformance.retroactiveContextDescriptor != nil
        let conditionalRequirementsCount = conformance.conditionalRequirements.count
        let conditionalPackShapeDescriptorsCount = conformance.conditionalPackShapeDescriptors.count
        let hasResilientWitnessesHeader = conformance.resilientWitnessesHeader != nil
        let resilientWitnessesCount = conformance.resilientWitnesses.count
        let hasGenericWitnessTable = conformance.genericWitnessTable != nil
        let hasGlobalActorReference = conformance.globalActorReference != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            flagsRawValue: \(raw: BaselineEmitter.hex(flagsRawValue)),
            hasProtocol: \(literal: hasProtocol),
            hasWitnessTablePattern: \(literal: hasWitnessTablePattern),
            hasRetroactiveContextDescriptor: \(literal: hasRetroactiveContextDescriptor),
            conditionalRequirementsCount: \(literal: conditionalRequirementsCount),
            conditionalPackShapeDescriptorsCount: \(literal: conditionalPackShapeDescriptorsCount),
            hasResilientWitnessesHeader: \(literal: hasResilientWitnessesHeader),
            resilientWitnessesCount: \(literal: resilientWitnessesCount),
            hasGenericWitnessTable: \(literal: hasGenericWitnessTable),
            hasGlobalActorReference: \(literal: hasGlobalActorReference)
        )
        """
        return expr.description
    }
}
