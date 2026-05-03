import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolDescriptorFlagsBaseline.swift`.
///
/// `ProtocolDescriptorFlags` is the standalone 32-bit flag word used by
/// the runtime metadata sections (NOT the kind-specific flags reachable
/// via `ContextDescriptorFlags`). It exposes `isSwift`, `isResilient`,
/// `classConstraint`, `dispatchStrategy`, `specialProtocolKind`, and
/// `needsProtocolWitnessTable` accessors plus `init(rawValue:)` and
/// `rawValue` storage.
///
/// The fixture has no live `ProtocolDescriptorFlags` instance to source
/// from (it's a Runtime/ABI structure synthesized in-process), so the
/// baseline records canonical bit patterns from synthetic raw values
/// covering each accessor branch:
///   - Swift (default): `0x1` (`isSwift: true`).
///   - Resilient + Swift: `0x401`.
///   - ObjC dispatch (`isSwift: false`, dispatchStrategy = objc): `0x0`.
package enum ProtocolDescriptorFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let swiftEntry = emitEntryExpr(rawValue: 0x1)
        let resilientEntry = emitEntryExpr(rawValue: 0x401)
        let objcEntry = emitEntryExpr(rawValue: 0x0)

        // Public members declared directly in ProtocolDescriptorFlags.swift.
        // `init(rawValue:)` is the synthesized memberwise initializer.
        let registered = [
            "classConstraint",
            "dispatchStrategy",
            "init(rawValue:)",
            "isResilient",
            "isSwift",
            "needsProtocolWitnessTable",
            "rawValue",
            "specialProtocolKind",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ProtocolDescriptorFlags has no live SymbolTestsCore source, so the
        // baseline embeds synthetic raw values that exercise each branch
        // (Swift default, Swift+resilient, ObjC dispatch).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let isSwift: Bool
                let isResilient: Bool
                let classConstraintRawValue: UInt8
                let dispatchStrategyRawValue: UInt8
                let specialProtocolKindRawValue: UInt8
                let needsProtocolWitnessTable: Bool
            }

            static let swift = \(raw: swiftEntry)

            static let resilient = \(raw: resilientEntry)

            static let objc = \(raw: objcEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(rawValue: UInt32) -> String {
        let flags = ProtocolDescriptorFlags(rawValue: rawValue)
        let isSwift = flags.isSwift
        let isResilient = flags.isResilient
        let classConstraintRawValue = flags.classConstraint.rawValue
        let dispatchStrategyRawValue = flags.dispatchStrategy.rawValue
        let specialProtocolKindRawValue = flags.specialProtocolKind.rawValue
        let needsProtocolWitnessTable = flags.needsProtocolWitnessTable

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            isSwift: \(literal: isSwift),
            isResilient: \(literal: isResilient),
            classConstraintRawValue: \(raw: BaselineEmitter.hex(classConstraintRawValue)),
            dispatchStrategyRawValue: \(raw: BaselineEmitter.hex(dispatchStrategyRawValue)),
            specialProtocolKindRawValue: \(raw: BaselineEmitter.hex(specialProtocolKindRawValue)),
            needsProtocolWitnessTable: \(literal: needsProtocolWitnessTable)
        )
        """
        return expr.description
    }
}
