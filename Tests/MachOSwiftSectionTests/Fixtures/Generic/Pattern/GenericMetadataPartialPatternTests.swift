import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericMetadataPartialPattern`.
///
/// The carrier is the extra-data block trailing
/// `GenericClassNonRequirement<A>`'s class pattern — the one partial pattern
/// the fixture contains.
@Suite
final class GenericMetadataPartialPatternTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericMetadataPartialPattern"
    static var registeredTestMethodNames: Set<String> {
        GenericMetadataPartialPatternBaseline.registeredTestMethodNames
    }

    private func loadPartialPatterns() throws -> (file: GenericMetadataPartialPattern, image: GenericMetadataPartialPattern) {
        let filePattern = try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOFile)
        let imagePattern = try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOImage)
        return (
            file: try required(try filePattern.partialPatterns(in: machOFile).first),
            image: try required(try imagePattern.partialPatterns(in: machOImage).first)
        )
    }

    @Test func offset() async throws {
        let partialPatterns = try loadPartialPatterns()
        let result = try acrossAllReaders(
            file: { partialPatterns.file.offset },
            image: { partialPatterns.image.offset }
        )
        #expect(result == GenericMetadataPartialPatternBaseline.offset)
    }

    @Test func layout() async throws {
        let partialPatterns = try loadPartialPatterns()
        let relativeOffset = try acrossAllReaders(
            file: { partialPatterns.file.layout.pattern.relativeOffset },
            image: { partialPatterns.image.layout.pattern.relativeOffset }
        )
        #expect(relativeOffset != 0)
        // One relative pointer plus two half-words; the pattern's own size
        // arithmetic depends on it.
        #expect(MemoryLayout<GenericMetadataPartialPattern.Layout>.size == 8)
    }

    @Test func patternOffset() async throws {
        let partialPatterns = try loadPartialPatterns()
        let result = try acrossAllReaders(
            file: { partialPatterns.file.patternOffset },
            image: { partialPatterns.image.patternOffset }
        )
        #expect(result == GenericMetadataPartialPatternBaseline.patternOffset)
    }

    /// Both quantities are counted in WORDS, not bytes — reading them as
    /// bytes would place the block eight times too close to the metadata's
    /// start.
    @Test func offsetInWords() async throws {
        let partialPatterns = try loadPartialPatterns()
        let result = try acrossAllReaders(
            file: { partialPatterns.file.offsetInWords },
            image: { partialPatterns.image.offsetInWords }
        )
        #expect(result == GenericMetadataPartialPatternBaseline.offsetInWords)
    }

    @Test func sizeInWords() async throws {
        let partialPatterns = try loadPartialPatterns()
        let result = try acrossAllReaders(
            file: { partialPatterns.file.sizeInWords },
            image: { partialPatterns.image.sizeInWords }
        )
        #expect(result == GenericMetadataPartialPatternBaseline.sizeInWords)
        #expect(result > 0)
    }
}
