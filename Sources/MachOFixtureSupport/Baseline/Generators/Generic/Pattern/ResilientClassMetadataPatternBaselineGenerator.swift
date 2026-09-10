import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ResilientClassMetadataPatternBaseline.swift`.
package enum ResilientClassMetadataPatternBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let pattern = try GenericMetadataPatternFixtures(in: machO).resilientClassPattern

        let registered = [
            "classFlags",
            "dataOffset",
            "destroyOffset",
            "instanceVariableDestroyerOffset",
            "layout",
            "metaclassOffset",
            "offset",
            "relocationFunctionOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The pattern of ResilientClassFixtures.ResilientChild — a
        // NON-generic class whose superclass lives in another resilience
        // domain, so its pattern hangs off the singleton metadata
        // initialization record rather than off a generic context.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ResilientClassMetadataPatternBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let offset = \(raw: BaselineEmitter.hex(pattern.offset))
            static let classFlags: UInt32 = \(raw: BaselineEmitter.hex(pattern.classFlags))
            static let relocationFunctionOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.relocationFunctionOffset))
            static let destroyOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.destroyOffset))
            static let instanceVariableDestroyerOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.instanceVariableDestroyerOffset))
            static let dataOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.dataOffset))
            static let metaclassOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.metaclassOffset))
        }
        """

        let formatted = file.formatted().description + "\n"
        try formatted.write(to: outputDirectory.appendingPathComponent("ResilientClassMetadataPatternBaseline.swift"), atomically: true, encoding: .utf8)
    }
}
