import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolRequirementBaseline.swift`.
///
/// `ProtocolRequirement` is the trailing-object record describing a single
/// requirement (method, property accessor, associated-type access function,
/// etc.) on a Swift protocol. It exposes `flags` (the
/// `ProtocolRequirementFlags` bit field) and `defaultImplementation` (a
/// relative pointer to a default-implementation symbol when the protocol
/// extension provides one).
///
/// Picker: `Protocols.ProtocolWitnessTableTest` — its 5 method
/// requirements (`a`/`b`/`c`/`d`/`e`) flesh out the trailing array; we
/// pick the first requirement and exercise its accessors.
///
/// The companion `ProtocolBaseRequirement` type (declared in the same
/// `ProtocolRequirement.swift` file) gets its own baseline / Suite
/// (`ProtocolBaseRequirementBaseline` / `ProtocolBaseRequirementTests`).
package enum ProtocolRequirementBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machO)
        let protocolType = try `Protocol`(descriptor: descriptor, in: machO)
        let firstRequirement = try required(protocolType.requirements.first)

        let firstRequirementExpr = try emitRequirementEntryExpr(for: firstRequirement, in: machO)

        // Public members declared on `ProtocolRequirement` (the first struct
        // in ProtocolRequirement.swift). `init(layout:offset:)` is filtered
        // as memberwise-synthesized.
        // Symbol attribution (`defaultImplementationSymbols(in:)`) lives in
        // SwiftInspection since evolution proposal `self-contained-abi-layer`;
        // the ABI layer exposes the default implementation's offset and
        // context address.
        let registered = [
            "defaultImplementationAddress",
            "defaultImplementationOffset",
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

        enum ProtocolRequirementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let defaultImplementationOffset: Int?
            }

            static let firstRequirement = \(raw: firstRequirementExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolRequirementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitRequirementEntryExpr(
        for requirement: ProtocolRequirement,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = requirement.offset
        let layoutFlagsRawValue = requirement.layout.flags.rawValue
        let defaultImplementationOffset = requirement.defaultImplementationOffset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(layoutFlagsRawValue)),
            defaultImplementationOffset: \(raw: BaselineEmitter.optionalHex(defaultImplementationOffset))
        )
        """
        return expr.description
    }
}
