import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolConformanceDescriptorBaseline.swift`.
///
/// `ProtocolConformanceDescriptor` is the raw section-level descriptor
/// pulled from `__swift5_proto`. The wrapper exposes the layout-trio
/// (`offset`, `layout`, `init(layout:offset:)` — the last filtered as
/// memberwise-synthesized), the `typeReference` computed property (turns
/// the layout's relative offset + type-reference-kind flag into a
/// `TypeReference` enum), plus three same-file extension helpers
/// (`protocolDescriptor`, `resolvedTypeReference`, `witnessTablePattern`)
/// each with three reader overloads (MachO + InProcess + ReadingContext)
/// that all collapse to a single MethodKey under the scanner's name-based
/// deduplication.
///
/// Picker: `Structs.StructTest: Protocols.ProtocolTest` — the simplest
/// path: a non-retroactive struct conformance with a resolvable witness
/// table and a `directTypeDescriptor` type reference.
package enum ProtocolConformanceDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let conformance = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machO)
        let descriptor = conformance.descriptor

        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared directly in ProtocolConformanceDescriptor.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        // The three reader overloads of `protocolDescriptor`, `resolvedTypeReference`,
        // and `witnessTablePattern` each collapse to one MethodKey.
        let registered = [
            "layout",
            "offset",
            "protocolDescriptor",
            "resolvedTypeReference",
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

        enum ProtocolConformanceDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let typeReferenceKindRawValue: UInt8
                let hasProtocolDescriptor: Bool
                let hasWitnessTablePattern: Bool
                let resolvedTypeReferenceIsDirectTypeDescriptor: Bool
            }

            static let structTestProtocolTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolConformanceDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: ProtocolConformanceDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let layoutFlagsRawValue = descriptor.layout.flags.rawValue
        let typeReferenceKindRawValue = descriptor.layout.flags.typeReferenceKind.rawValue
        let hasProtocolDescriptor = (try descriptor.protocolDescriptor(in: machO)) != nil
        let hasWitnessTablePattern = (try descriptor.witnessTablePattern(in: machO)) != nil
        let resolvedTypeReference = try descriptor.resolvedTypeReference(in: machO)
        let isDirectTypeDescriptor: Bool
        if case .directTypeDescriptor = resolvedTypeReference {
            isDirectTypeDescriptor = true
        } else {
            isDirectTypeDescriptor = false
        }

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(layoutFlagsRawValue)),
            typeReferenceKindRawValue: \(raw: BaselineEmitter.hex(typeReferenceKindRawValue)),
            hasProtocolDescriptor: \(literal: hasProtocolDescriptor),
            hasWitnessTablePattern: \(literal: hasWitnessTablePattern),
            resolvedTypeReferenceIsDirectTypeDescriptor: \(literal: isDirectTypeDescriptor)
        )
        """
        return expr.description
    }
}
