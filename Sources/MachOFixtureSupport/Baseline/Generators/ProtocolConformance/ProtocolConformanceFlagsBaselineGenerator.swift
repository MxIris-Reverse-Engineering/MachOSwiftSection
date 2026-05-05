import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolConformanceFlagsBaseline.swift`.
///
/// `ProtocolConformanceFlags` is the 32-bit flag word stored in
/// `ProtocolConformanceDescriptor.Layout.flags`. It packs the
/// `typeReferenceKind` (low 3 bits, shifted by 3), three boolean bits
/// (isRetroactive / isSynthesizedNonUnique / isConformanceOfProtocol),
/// the resilient/generic/global-actor witness-table presence bits, the
/// `numConditionalRequirements` byte, and the
/// `numConditionalPackShapeDescriptors` byte.
///
/// Three pickers feed the baseline so each branch is witnessed by at
/// least one entry:
///   - `Structs.StructTest: Protocols.ProtocolTest` — the simplest
///     baseline path: defaultDirectTypeDescriptor kind, all flags clear,
///     zero conditional requirements.
///   - The first conditional conformance — surfaces a non-zero
///     `numConditionalRequirements` value.
///   - The first global-actor-isolated conformance — surfaces
///     `hasGlobalActorIsolation: true`.
///   - The first resilient-witness conformance — surfaces
///     `hasResilientWitnesses: true`.
package enum ProtocolConformanceFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machO)
        let conditional = try BaselineFixturePicker.protocolConformance_conditionalFirst(in: machO)
        let globalActor = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machO)
        let resilient = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machO)

        let structTestExpr = emitEntryExpr(rawValue: structTest.flags.rawValue)
        let conditionalExpr = emitEntryExpr(rawValue: conditional.flags.rawValue)
        let globalActorExpr = emitEntryExpr(rawValue: globalActor.flags.rawValue)
        let resilientExpr = emitEntryExpr(rawValue: resilient.flags.rawValue)

        // Public members declared directly in ProtocolConformanceFlags.swift.
        let registered = [
            "hasGenericWitnessTable",
            "hasGlobalActorIsolation",
            "hasNonDefaultSerialExecutorIsIsolatingCurrentContext",
            "hasResilientWitnesses",
            "init(rawValue:)",
            "isConformanceOfProtocol",
            "isRetroactive",
            "isSynthesizedNonUnique",
            "numConditionalPackShapeDescriptors",
            "numConditionalRequirements",
            "rawValue",
            "typeReferenceKind",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolConformanceFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let typeReferenceKindRawValue: UInt8
                let isRetroactive: Bool
                let isSynthesizedNonUnique: Bool
                let isConformanceOfProtocol: Bool
                let hasGlobalActorIsolation: Bool
                let hasNonDefaultSerialExecutorIsIsolatingCurrentContext: Bool
                let hasResilientWitnesses: Bool
                let hasGenericWitnessTable: Bool
                let numConditionalRequirements: UInt32
                let numConditionalPackShapeDescriptors: UInt32
            }

            static let structTestProtocolTest = \(raw: structTestExpr)

            static let conditionalFirst = \(raw: conditionalExpr)

            static let globalActorFirst = \(raw: globalActorExpr)

            static let resilientFirst = \(raw: resilientExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolConformanceFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = ProtocolConformanceFlags(rawValue: rawValue)

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            typeReferenceKindRawValue: \(raw: BaselineEmitter.hex(flags.typeReferenceKind.rawValue)),
            isRetroactive: \(literal: flags.isRetroactive),
            isSynthesizedNonUnique: \(literal: flags.isSynthesizedNonUnique),
            isConformanceOfProtocol: \(literal: flags.isConformanceOfProtocol),
            hasGlobalActorIsolation: \(literal: flags.hasGlobalActorIsolation),
            hasNonDefaultSerialExecutorIsIsolatingCurrentContext: \(literal: flags.hasNonDefaultSerialExecutorIsIsolatingCurrentContext),
            hasResilientWitnesses: \(literal: flags.hasResilientWitnesses),
            hasGenericWitnessTable: \(literal: flags.hasGenericWitnessTable),
            numConditionalRequirements: \(raw: BaselineEmitter.hex(flags.numConditionalRequirements)),
            numConditionalPackShapeDescriptors: \(raw: BaselineEmitter.hex(flags.numConditionalPackShapeDescriptors))
        )
        """
        return expr.description
    }
}
