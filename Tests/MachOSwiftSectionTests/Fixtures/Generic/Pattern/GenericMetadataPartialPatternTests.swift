import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `GenericMetadataPartialPattern`.
///
/// The carrier is the extra-data block trailing
/// `GenericClassNonRequirement<A>`'s class pattern — the one partial pattern
/// the fixture contains.
@Suite
@FixtureSuite
final class GenericMetadataPartialPatternTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadPartialPatterns() throws -> (file: GenericMetadataPartialPattern, image: GenericMetadataPartialPattern) {
        let filePattern = try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOFile)
        let imagePattern = try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOImage)
        return (
            file: try required(try filePattern.partialPatterns(in: fileContext).first),
            image: try required(try imagePattern.partialPatterns(in: imageContext).first)
        )
    }

    @Test func offset() async throws {
        let partialPatterns = try loadPartialPatterns()
        let result = try acrossAllReaders(partialPatterns.file, partialPatterns.image) { $0.offset }
        #expect(result == GenericMetadataPartialPatternBaseline.offset)
    }

    @Test func layout() async throws {
        let partialPatterns = try loadPartialPatterns()
        let relativeOffset = try acrossAllReaders(partialPatterns.file, partialPatterns.image) { partialPattern in
            partialPattern.layout.pattern.relativeOffset
        }
        #expect(relativeOffset != 0)
        // One relative pointer plus two half-words; the pattern's own size
        // arithmetic depends on it.
        #expect(MemoryLayout<GenericMetadataPartialPattern.Layout>.size == 8)

        let patternOffset = try acrossAllReaders(partialPatterns.file, partialPatterns.image) { partialPattern in
            partialPattern.resolvedDirectOffset(from: \.pattern)
        }
        #expect(patternOffset == GenericMetadataPartialPatternBaseline.patternOffset)

        // Both quantities are counted in WORDS, not bytes — reading them as
        // bytes would place the block eight times too close to the metadata's
        // start.
        let wordCounts = try acrossAllReaders(partialPatterns.file, partialPatterns.image) { partialPattern in
            [partialPattern.layout.offsetInWords, partialPattern.layout.sizeInWords]
        }
        #expect(wordCounts.map(Int.init) == [
            GenericMetadataPartialPatternBaseline.offsetInWords,
            GenericMetadataPartialPatternBaseline.sizeInWords,
        ])
        #expect(wordCounts[1] > 0)
    }

}
