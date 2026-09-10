import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericMetadataPartialPatternBaseline.swift`.
///
/// The one partial pattern in the fixture: the extra-data block of
/// `GenericClassNonRequirement<A>`'s class pattern.
package enum GenericMetadataPartialPatternBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let classPattern = try GenericMetadataPatternFixtures(in: machO).classPattern
        let partialPattern = try required(try classPattern.partialPatterns(in: machO).first)

        let registered = ["layout", "offset", "offsetInWords", "patternOffset", "sizeInWords"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The extra-data partial pattern trailing
        // GenericClassNonRequirement<A>'s class metadata pattern.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericMetadataPartialPatternBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            static let offset = \(raw: BaselineEmitter.hex(partialPattern.offset))
            static let patternOffset: Int? = \(raw: BaselineEmitter.optionalHex(partialPattern.patternOffset))
            static let offsetInWords = \(literal: partialPattern.offsetInWords)
            static let sizeInWords = \(literal: partialPattern.sizeInWords)
        }
        """

        let formatted = file.formatted().description + "\n"
        try formatted.write(to: outputDirectory.appendingPathComponent("GenericMetadataPartialPatternBaseline.swift"), atomically: true, encoding: .utf8)
    }
}
