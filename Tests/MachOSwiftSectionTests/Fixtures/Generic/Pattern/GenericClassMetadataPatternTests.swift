import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericClassMetadataPattern`.
///
/// The carrier is `GenericFieldLayout.GenericClassNonRequirement<A>` — the
/// simplest generic class in the fixture, and the only pattern that trails a
/// partial pattern.
@Suite
final class GenericClassMetadataPatternTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericClassMetadataPattern"
    static var registeredTestMethodNames: Set<String> {
        GenericClassMetadataPatternBaseline.registeredTestMethodNames
    }

    private func loadPatterns() throws -> (file: GenericClassMetadataPattern, image: GenericClassMetadataPattern) {
        (
            file: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOFile),
            image: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOImage)
        )
    }

    @Test func offset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.offset },
            image: { patterns.image.offset }
        )
        #expect(result == GenericClassMetadataPatternBaseline.offset)
    }

    @Test func layout() async throws {
        let patterns = try loadPatterns()
        let flagsRaw = try acrossAllReaders(
            file: { patterns.file.layout.patternFlags.rawValue },
            image: { patterns.image.layout.patternFlags.rawValue }
        )
        #expect(flagsRaw == GenericClassMetadataPatternBaseline.patternFlagsRawValue)
        // Three header words, two function pointers, the class flag word and
        // four half-words of interop offsets.
        #expect(MemoryLayout<GenericClassMetadataPattern.Layout>.size == 32)

        let classFlags = try acrossAllReaders(
            file: { patterns.file.layout.classFlags },
            image: { patterns.image.layout.classFlags }
        )
        #expect(classFlags == GenericClassMetadataPatternBaseline.classFlags)

        // Where the runtime-built class_ro_t and metaclass land inside the
        // extra data block, counted in WORDS.
        let interopOffsetsInWords = try acrossAllReaders(
            file: {
                [
                    patterns.file.layout.classReadOnlyDataOffsetInWords,
                    patterns.file.layout.metaclassObjectOffsetInWords,
                    patterns.file.layout.metaclassReadOnlyDataOffsetInWords,
                ]
            },
            image: {
                [
                    patterns.image.layout.classReadOnlyDataOffsetInWords,
                    patterns.image.layout.metaclassObjectOffsetInWords,
                    patterns.image.layout.metaclassReadOnlyDataOffsetInWords,
                ]
            }
        )
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
            let resolved = try acrossAllReaders(
                file: { patterns.file.resolvedDirectOffset(from: keyPath) },
                image: { patterns.image.resolvedDirectOffset(from: keyPath) }
            )
            #expect(resolved == expected)
        }
    }

    /// Bit 31 means "an immediate-members pattern trails" on a class pattern
    /// and "top bit of the metadata kind" on a value pattern. Reading it on
    /// the wrong one is how a trailing-array walk goes off the end, so the
    /// value carrier is checked here too.
    @Test func hasImmediateMembersPattern() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.hasImmediateMembersPattern },
            image: { patterns.image.hasImmediateMembersPattern }
        )
        #expect(result == GenericClassMetadataPatternBaseline.hasImmediateMembersPattern)

        let valuePattern = try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOFile)
        #expect(valuePattern.patternFlags.valueMetadataKindRawValue != 0, "the value carrier must actually have bits set in the overlapping region")
        #expect(valuePattern.numberOfTrailingPartialPatterns == 0, "a value pattern must not count the class-only bit")
    }

    @Test func numberOfTrailingPartialPatterns() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.numberOfTrailingPartialPatterns },
            image: { patterns.image.numberOfTrailingPartialPatterns }
        )
        #expect(result == GenericClassMetadataPatternBaseline.numberOfTrailingPartialPatterns)
        #expect(result == (patterns.file.hasExtraDataPattern ? 1 : 0) + (patterns.file.hasImmediateMembersPattern ? 1 : 0))
    }

    @Test func immediateMembersPattern() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { try patterns.file.immediateMembersPattern(in: machOFile)?.offset },
            image: { try patterns.image.immediateMembersPattern(in: machOImage)?.offset }
        )
        // This carrier has no immediate-members pattern; the accessor must
        // answer nil rather than hand back the extra-data one.
        #expect(result == nil)
        #expect(GenericClassMetadataPatternBaseline.hasImmediateMembersPattern == false)
        #expect(try patterns.file.partialPatterns(in: machOFile).count == 1)
    }
}
