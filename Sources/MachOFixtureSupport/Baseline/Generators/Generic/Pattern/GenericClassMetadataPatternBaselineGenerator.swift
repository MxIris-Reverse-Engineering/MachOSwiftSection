import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericClassMetadataPatternBaseline.swift`.
package enum GenericClassMetadataPatternBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let pattern = try GenericMetadataPatternFixtures(in: machO).classPattern

        let registered = [
            "classFlags",
            "completionFunctionOffset",
            "classReadOnlyDataOffsetInWords",
            "destroyOffset",
            "hasImmediateMembersPattern",
            "instantiationFunctionOffset",
            "immediateMembersPattern",
            "instanceVariableDestroyerOffset",
            "layout",
            "metaclassObjectOffsetInWords",
            "metaclassReadOnlyDataOffsetInWords",
            "numberOfTrailingPartialPatterns",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The instantiation pattern of GenericFieldLayout's
        // GenericClassNonRequirement<A>, reached through the type's generic
        // context header.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericClassMetadataPatternBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let offset = \(raw: BaselineEmitter.hex(pattern.offset))
            static let patternFlagsRawValue: UInt32 = \(raw: BaselineEmitter.hex(pattern.patternFlags.rawValue))
            static let classFlags: UInt32 = \(raw: BaselineEmitter.hex(pattern.classFlags))
            static let hasExtraDataPattern = \(literal: pattern.hasExtraDataPattern)
            static let hasImmediateMembersPattern = \(literal: pattern.hasImmediateMembersPattern)
            static let numberOfTrailingPartialPatterns = \(literal: pattern.numberOfTrailingPartialPatterns)
            static let instantiationFunctionOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.instantiationFunctionOffset))
            static let completionFunctionOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.completionFunctionOffset))
            static let destroyOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.destroyOffset))
            static let instanceVariableDestroyerOffset: Int? = \(raw: BaselineEmitter.optionalHex(pattern.instanceVariableDestroyerOffset))
            static let classReadOnlyDataOffsetInWords = \(literal: pattern.classReadOnlyDataOffsetInWords)
            static let metaclassObjectOffsetInWords = \(literal: pattern.metaclassObjectOffsetInWords)
            static let metaclassReadOnlyDataOffsetInWords = \(literal: pattern.metaclassReadOnlyDataOffsetInWords)
        }
        """

        let formatted = file.formatted().description + "\n"
        try formatted.write(to: outputDirectory.appendingPathComponent("GenericClassMetadataPatternBaseline.swift"), atomically: true, encoding: .utf8)
    }
}
