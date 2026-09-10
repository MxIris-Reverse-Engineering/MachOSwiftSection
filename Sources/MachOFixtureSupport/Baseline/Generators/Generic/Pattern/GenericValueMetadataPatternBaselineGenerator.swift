import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericValueMetadataPatternBaseline.swift`.
package enum GenericValueMetadataPatternBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let pattern = try GenericMetadataPatternFixtures(in: machO).valuePattern

        let registered = [
            "completionFunctionOffset",
            "instantiationFunctionOffset",
            "layout",
            "metadataKind",
            "numberOfTrailingPartialPatterns",
            "offset",
            "valueWitnessesIsIndirect",
            "valueWitnessesOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The instantiation pattern of GenericFieldLayout's
        // GenericStructNonRequirement<A>, reached through the type's generic
        // context header — the same route the runtime takes.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericValueMetadataPatternBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let offset = \(raw: BaselineEmitter.hex(pattern.offset))
            static let patternFlagsRawValue: UInt32 = \(raw: BaselineEmitter.hex(pattern.patternFlags.rawValue))
            static let metadataKindRawValue: UInt32? = \(raw: BaselineEmitter.optionalHex(pattern.metadataKind?.rawValue))
            static let numberOfTrailingPartialPatterns = \(literal: pattern.numberOfTrailingPartialPatterns)
            static let valueWitnessesOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.valueWitnessesOffset))
            static let valueWitnessesIsIndirect = \(literal: pattern.valueWitnessesIsIndirect)
            static let instantiationFunctionOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.instantiationFunctionOffset))
            static let completionFunctionOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.completionFunctionOffset))
        }
        """

        let formatted = file.formatted().description + "\n"
        try formatted.write(to: outputDirectory.appendingPathComponent("GenericValueMetadataPatternBaseline.swift"), atomically: true, encoding: .utf8)
    }
}
