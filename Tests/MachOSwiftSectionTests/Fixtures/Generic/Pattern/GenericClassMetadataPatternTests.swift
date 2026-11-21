import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport
import BinaryParseSupport

/// Fixture-based Suite for `GenericClassMetadataPattern`.
///
/// The carrier is `GenericFieldLayout.GenericClassNonRequirement<A>` — the
/// simplest generic class in the fixture, and the only pattern that trails a
/// partial pattern.
@Suite
@FixtureSuite
final class GenericClassMetadataPatternTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadPatterns() throws -> (file: GenericClassMetadataPattern, image: GenericClassMetadataPattern) {
        (
            file: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOFile),
            image: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOImage)
        )
    }

    @Test func offset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(patterns.file, patterns.image) { $0.offset }
        #expect(result == GenericClassMetadataPatternBaseline.offset)
    }

    @Test func layout() async throws {
        let patterns = try loadPatterns()
        let flagsRaw = try acrossAllReaders(patterns.file, patterns.image) { $0.layout.patternFlags.rawValue }
        #expect(flagsRaw == GenericClassMetadataPatternBaseline.patternFlagsRawValue)
        // Three header words, two function pointers, the class flag word and
        // four half-words of interop offsets.
        #expect(MemoryLayout<GenericClassMetadataPattern.Layout>.size == 32)

        let classFlags = try acrossAllReaders(patterns.file, patterns.image) { $0.layout.classFlags }
        #expect(classFlags == GenericClassMetadataPatternBaseline.classFlags)

        // Where the runtime-built class_ro_t and metaclass land inside the
        // extra data block, counted in WORDS.
        let interopOffsetsInWords = try acrossAllReaders(patterns.file, patterns.image) { pattern in
            [
                pattern.layout.classReadOnlyDataOffsetInWords,
                pattern.layout.metaclassObjectOffsetInWords,
                pattern.layout.metaclassReadOnlyDataOffsetInWords,
            ]
        }
        #expect(interopOffsetsInWords.map(Int.init) == [
            GenericClassMetadataPatternBaseline.classReadOnlyDataOffsetInWords,
            GenericClassMetadataPatternBaseline.metaclassObjectOffsetInWords,
            GenericClassMetadataPatternBaseline.metaclassReadOnlyDataOffsetInWords,
        ])

        // The four relative pointers, all pure arithmetic. A null
        // instance-variable destructor means the class needs none.
        for (keyPath, expected) in [
            (\GenericClassMetadataPattern.Layout.instantiationFunction, GenericClassMetadataPatternBaseline.instantiationFunctionOffset),
            (\GenericClassMetadataPattern.Layout.completionFunction, GenericClassMetadataPatternBaseline.completionFunctionOffset),
            (\GenericClassMetadataPattern.Layout.destroy, GenericClassMetadataPatternBaseline.destroyOffset),
            (\GenericClassMetadataPattern.Layout.instanceVariableDestroyer, GenericClassMetadataPatternBaseline.instanceVariableDestroyerOffset),
        ] {
            let resolved = try acrossAllReaders(patterns.file, patterns.image) { $0.resolvedDirectOffset(from: keyPath) }
            #expect(resolved == expected)
        }
    }

    /// Bit 31 means "an immediate-members pattern trails" on a class pattern
    /// and "top bit of the metadata kind" on a value pattern. Reading it on
    /// the wrong one is how a trailing-array walk goes off the end, so the
    /// value carrier is checked here too.
    @Test func hasImmediateMembersPattern() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(patterns.file, patterns.image) { $0.hasImmediateMembersPattern }
        #expect(result == GenericClassMetadataPatternBaseline.hasImmediateMembersPattern)

        let valuePattern = try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOFile)
        #expect(valuePattern.patternFlags.valueMetadataKindRawValue != 0, "the value carrier must actually have bits set in the overlapping region")
        #expect(valuePattern.numberOfTrailingPartialPatterns == 0, "a value pattern must not count the class-only bit")
    }

    @Test func numberOfTrailingPartialPatterns() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(patterns.file, patterns.image) { $0.numberOfTrailingPartialPatterns }
        #expect(result == GenericClassMetadataPatternBaseline.numberOfTrailingPartialPatterns)
        #expect(result == (patterns.file.hasExtraDataPattern ? 1 : 0) + (patterns.file.hasImmediateMembersPattern ? 1 : 0))
    }

    @Test func immediateMembersPattern() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllContexts(patterns.file, patterns.image) { pattern, context in
            try pattern.immediateMembersPattern(in: context)?.offset
        }
        // This carrier has no immediate-members pattern; the accessor must
        // answer nil rather than hand back the extra-data one.
        #expect(result == nil)
        #expect(GenericClassMetadataPatternBaseline.hasImmediateMembersPattern == false)
        #expect(try patterns.file.partialPatterns(in: fileContext).count == 1)
    }
}
