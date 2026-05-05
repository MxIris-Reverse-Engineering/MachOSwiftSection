import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOExtensions
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolContextDescriptorFlagsBaseline.swift`.
///
/// `ProtocolContextDescriptorFlags` is the kind-specific 16-bit `FlagSet`
/// reachable via `ContextDescriptorFlags.kindSpecificFlags?.protocolFlags`
/// for protocol-kind context descriptors. It exposes `isResilient`,
/// `classConstraint`, and `specialProtocolKind` accessors plus the
/// `init(rawValue:)` synthesized initializer and the `rawValue` storage.
///
/// Picker: `Protocols.ProtocolTest` — its kind-specific flags slot
/// resolves to a real `ProtocolContextDescriptorFlags` value.
package enum ProtocolContextDescriptorFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machO)
        let flags = try required(descriptor.layout.flags.kindSpecificFlags?.protocolFlags)
        let entryExpr = emitEntryExpr(for: flags)

        // Public members declared directly in ProtocolContextDescriptorFlags.swift.
        let registered = [
            "classConstraint",
            "init(rawValue:)",
            "isResilient",
            "rawValue",
            "specialProtocolKind",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolContextDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt16
                let isResilient: Bool
                let classConstraintRawValue: UInt8
                let specialProtocolKindRawValue: UInt8
            }

            static let protocolTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolContextDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: ProtocolContextDescriptorFlags) -> String {
        let rawValue = flags.rawValue
        let isResilient = flags.isResilient
        let classConstraintRawValue = flags.classConstraint.rawValue
        let specialProtocolKindRawValue = flags.specialProtocolKind.rawValue

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            isResilient: \(literal: isResilient),
            classConstraintRawValue: \(raw: BaselineEmitter.hex(classConstraintRawValue)),
            specialProtocolKindRawValue: \(raw: BaselineEmitter.hex(specialProtocolKindRawValue))
        )
        """
        return expr.description
    }
}
