import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolBaseline.swift`.
///
/// `Protocol` is the high-level wrapper around `ProtocolDescriptor` —
/// it eagerly materializes the descriptor's name, base requirement,
/// requirementInSignatures, and trailing `ProtocolRequirement` array.
///
/// Two pickers feed the baseline so multiple branches are witnessed:
///   - `Protocols.ProtocolTest` — exercises `requirementInSignatures`
///     (its `Body: ProtocolTest` associated-type constraint surfaces a
///     non-empty requirement-in-signature array).
///   - `Protocols.ProtocolWitnessTableTest` — exercises the trailing
///     `requirements` array (5 method requirements: `a`/`b`/`c`/`d`/`e`).
package enum ProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let protocolTestDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machO)
        let protocolTest = try `Protocol`(descriptor: protocolTestDescriptor, in: machO)
        let protocolTestExpr = emitEntryExpr(for: protocolTest)

        let witnessTableTestDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machO)
        let witnessTableTest = try `Protocol`(descriptor: witnessTableTestDescriptor, in: machO)
        let witnessTableTestExpr = emitEntryExpr(for: witnessTableTest)

        // Public members declared directly in Protocol.swift (across the main
        // body and two same-file extensions, both in the ReadingContext block).
        // Stored properties (descriptor/protocolFlags/name/baseRequirement/
        // requirementInSignatures/requirements) collapse with the two
        // `init(descriptor:in:)` overloads under PublicMemberScanner's name-
        // based deduplication.
        let registered = [
            "baseRequirement",
            "descriptor",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "name",
            "numberOfRequirements",
            "numberOfRequirementsInSignature",
            "protocolFlags",
            "requirementInSignatures",
            "requirements",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let name: String
                let descriptorOffset: Int
                let protocolFlagsRawValue: UInt16
                let numberOfRequirements: Int
                let numberOfRequirementsInSignature: Int
                let hasBaseRequirement: Bool
                let requirementsCount: Int
                let requirementInSignaturesCount: Int
            }

            static let protocolTest = \(raw: protocolTestExpr)

            static let protocolWitnessTableTest = \(raw: witnessTableTestExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for protocolType: MachOSwiftSection.`Protocol`) -> String {
        let name = protocolType.name
        let descriptorOffset = protocolType.descriptor.offset
        let protocolFlagsRawValue = protocolType.protocolFlags.rawValue
        let numberOfRequirements = protocolType.numberOfRequirements
        let numberOfRequirementsInSignature = protocolType.numberOfRequirementsInSignature
        let hasBaseRequirement = protocolType.baseRequirement != nil
        let requirementsCount = protocolType.requirements.count
        let requirementInSignaturesCount = protocolType.requirementInSignatures.count

        let expr: ExprSyntax = """
        Entry(
            name: \(literal: name),
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            protocolFlagsRawValue: \(raw: BaselineEmitter.hex(protocolFlagsRawValue)),
            numberOfRequirements: \(literal: numberOfRequirements),
            numberOfRequirementsInSignature: \(literal: numberOfRequirementsInSignature),
            hasBaseRequirement: \(literal: hasBaseRequirement),
            requirementsCount: \(literal: requirementsCount),
            requirementInSignaturesCount: \(literal: requirementInSignaturesCount)
        )
        """
        return expr.description
    }
}
