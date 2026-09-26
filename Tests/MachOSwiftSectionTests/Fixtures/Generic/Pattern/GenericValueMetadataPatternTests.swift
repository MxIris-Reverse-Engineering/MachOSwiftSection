import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericValueMetadataPattern`.
///
/// The carrier is `GenericFieldLayout.GenericStructNonRequirement<A>`,
/// reached the way the runtime reaches it — through the type's generic
/// context header — so the picker itself exercises
/// `TypeGenericContextDescriptorHeader.defaultInstantiationPatternOffset`.
@Suite
final class GenericValueMetadataPatternTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericValueMetadataPattern"
    static var registeredTestMethodNames: Set<String> {
        GenericValueMetadataPatternBaseline.registeredTestMethodNames
    }

    private func loadPatterns() throws -> (file: GenericValueMetadataPattern, image: GenericValueMetadataPattern) {
        (
            file: try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOFile),
            image: try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOImage)
        )
    }

    @Test func offset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.offset },
            image: { patterns.image.offset }
        )
        #expect(result == GenericValueMetadataPatternBaseline.offset)
    }

    @Test func layout() async throws {
        let patterns = try loadPatterns()
        let flagsRaw = try acrossAllReaders(
            file: { patterns.file.layout.patternFlags.rawValue },
            image: { patterns.image.layout.patternFlags.rawValue }
        )
        #expect(flagsRaw == GenericValueMetadataPatternBaseline.patternFlagsRawValue)
        // Three header words plus the value witness pointer.
        #expect(MemoryLayout<GenericValueMetadataPattern.Layout>.size == 16)

        let instantiationFunctionOffset = try acrossAllReaders(
            file: { patterns.file.resolvedDirectOffset(from: \.instantiationFunction) },
            image: { patterns.image.resolvedDirectOffset(from: \.instantiationFunction) }
        )
        #expect(instantiationFunctionOffset == GenericValueMetadataPatternBaseline.instantiationFunctionOffset)

        let completionFunctionOffset = try acrossAllReaders(
            file: { patterns.file.resolvedDirectOffset(from: \.completionFunction) },
            image: { patterns.image.resolvedDirectOffset(from: \.completionFunction) }
        )
        #expect(completionFunctionOffset == GenericValueMetadataPatternBaseline.completionFunctionOffset)
    }

    /// A value pattern's top flag bits are the metadata kind, not the class
    /// immediate-members bit — reading them the other way round is the
    /// mistake this accessor exists to prevent.
    @Test func metadataKind() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.metadataKind?.rawValue },
            image: { patterns.image.metadataKind?.rawValue }
        )
        #expect(result == GenericValueMetadataPatternBaseline.metadataKindRawValue)
        #expect(patterns.file.metadataKind == .struct)
    }

    @Test func numberOfTrailingPartialPatterns() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.numberOfTrailingPartialPatterns },
            image: { patterns.image.numberOfTrailingPartialPatterns }
        )
        #expect(result == GenericValueMetadataPatternBaseline.numberOfTrailingPartialPatterns)
        // A value pattern never counts the class-only immediate-members bit,
        // which on this carrier is set as part of the metadata kind.
        #expect(result == (patterns.file.hasExtraDataPattern ? 1 : 0))
    }

    /// The reason to model this type at all: for a generic type whose layout
    /// does not depend on its arguments, this table is the compiler's own
    /// answer for size, stride, alignment and extra inhabitants.
    @Test func valueWitnessesOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.valueWitnessesOffset },
            image: { patterns.image.valueWitnessesOffset }
        )
        #expect(result == GenericValueMetadataPatternBaseline.valueWitnessesOffset)
    }

    @Test func valueWitnessesIsIndirect() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.valueWitnessesIsIndirect },
            image: { patterns.image.valueWitnessesIsIndirect }
        )
        #expect(result == GenericValueMetadataPatternBaseline.valueWitnessesIsIndirect)
        // The two readings are mutually exclusive: an indirect pointer names
        // no offset within this image.
        #expect((patterns.file.valueWitnessesOffset == nil) || !result)
    }
}
