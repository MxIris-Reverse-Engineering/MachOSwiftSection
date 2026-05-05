import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolBaseRequirementBaseline.swift`.
///
/// `ProtocolBaseRequirement` is the empty-layout marker companion to
/// `ProtocolRequirement` (both declared in `ProtocolRequirement.swift`).
/// It carries no payload other than the trailing-object header offset.
///
/// Picker: `Protocols.ProtocolWitnessTableTest` — the protocol's
/// `baseRequirement` slot resolves to a live instance.
package enum ProtocolBaseRequirementBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machO)
        let protocolType = try `Protocol`(descriptor: descriptor, in: machO)
        let baseRequirement = try required(protocolType.baseRequirement)

        let entryExpr = emitEntryExpr(for: baseRequirement)

        // Public members declared on `ProtocolBaseRequirement` (the second
        // struct in ProtocolRequirement.swift). `init(layout:offset:)` is
        // filtered as memberwise-synthesized.
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

        enum ProtocolBaseRequirementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
            }

            static let witnessTableTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolBaseRequirementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for baseRequirement: ProtocolBaseRequirement) -> String {
        let offset = baseRequirement.offset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset))
        )
        """
        return expr.description
    }
}
