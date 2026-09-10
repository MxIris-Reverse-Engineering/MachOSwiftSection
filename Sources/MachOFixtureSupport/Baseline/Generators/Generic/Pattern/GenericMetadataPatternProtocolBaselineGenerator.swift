import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericMetadataPatternProtocolBaseline.swift`.
///
/// The members `GenericMetadataPatternProtocol` supplies to both conformers,
/// recorded for each so the shared implementation is pinned on a value
/// pattern and a class pattern alike — the class one is the only carrier with
/// a trailing partial pattern.
package enum GenericMetadataPatternProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let fixtures = try GenericMetadataPatternFixtures(in: machO)

        let registered = [
            "extraDataPattern",
            "hasExtraDataPattern",
            "hasTrailingFlags",
            "partialPatterns",
            "partialPatternsOffset",
            "patternFlags",
            "size",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The shared pattern-header members, recorded for both conformers.
        """

        func emitEntry(offset: Int, flags: UInt32, hasExtraDataPattern: Bool, hasTrailingFlags: Bool, instantiation: Int?, completion: Int?, partialPatternsOffset: Int, size: Int, partialPatternCount: Int) -> String {
            let expr: ExprSyntax = """
            Entry(
                offset: \(raw: BaselineEmitter.hex(offset)),
                patternFlagsRawValue: \(raw: BaselineEmitter.hex(flags)),
                hasExtraDataPattern: \(literal: hasExtraDataPattern),
                hasTrailingFlags: \(literal: hasTrailingFlags),
                instantiationFunctionOffset: \(raw: BaselineEmitter.optionalHex(instantiation)),
                completionFunctionOffset: \(raw: BaselineEmitter.optionalHex(completion)),
                partialPatternsOffset: \(raw: BaselineEmitter.hex(partialPatternsOffset)),
                size: \(literal: size),
                partialPatternCount: \(literal: partialPatternCount)
            )
            """
            return expr.description
        }

        let valueEntry = emitEntry(
            offset: fixtures.valuePattern.offset,
            flags: fixtures.valuePattern.patternFlags.rawValue,
            hasExtraDataPattern: fixtures.valuePattern.hasExtraDataPattern,
            hasTrailingFlags: fixtures.valuePattern.hasTrailingFlags,
            instantiation: fixtures.valuePattern.instantiationFunctionOffset,
            completion: fixtures.valuePattern.completionFunctionOffset,
            partialPatternsOffset: fixtures.valuePattern.partialPatternsOffset,
            size: fixtures.valuePattern.size,
            partialPatternCount: try fixtures.valuePattern.partialPatterns(in: machO).count
        )
        let classEntry = emitEntry(
            offset: fixtures.classPattern.offset,
            flags: fixtures.classPattern.patternFlags.rawValue,
            hasExtraDataPattern: fixtures.classPattern.hasExtraDataPattern,
            hasTrailingFlags: fixtures.classPattern.hasTrailingFlags,
            instantiation: fixtures.classPattern.instantiationFunctionOffset,
            completion: fixtures.classPattern.completionFunctionOffset,
            partialPatternsOffset: fixtures.classPattern.partialPatternsOffset,
            size: fixtures.classPattern.size,
            partialPatternCount: try fixtures.classPattern.partialPatterns(in: machO).count
        )

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericMetadataPatternProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let patternFlagsRawValue: UInt32
                let hasExtraDataPattern: Bool
                let hasTrailingFlags: Bool
                let instantiationFunctionOffset: Int?
                let completionFunctionOffset: Int?
                let partialPatternsOffset: Int
                let size: Int
                let partialPatternCount: Int
            }

            static let valuePattern = \(raw: valueEntry)

            static let classPattern = \(raw: classEntry)
        }
        """

        let formatted = file.formatted().description + "\n"
        try formatted.write(to: outputDirectory.appendingPathComponent("GenericMetadataPatternProtocolBaseline.swift"), atomically: true, encoding: .utf8)
    }
}
