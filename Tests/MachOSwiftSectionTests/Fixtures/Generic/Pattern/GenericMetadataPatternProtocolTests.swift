import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericMetadataPatternProtocol` — the members
/// both pattern kinds share.
///
/// Every assertion runs against both conformers, because the shared header
/// is the one part of the two layouts that must agree, and the class carrier
/// is the only one with a trailing partial pattern.
@Suite
final class GenericMetadataPatternProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericMetadataPatternProtocol"
    static var registeredTestMethodNames: Set<String> {
        GenericMetadataPatternProtocolBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let label: String
        let file: any GenericMetadataPatternProtocol
        let image: any GenericMetadataPatternProtocol
        let expected: GenericMetadataPatternProtocolBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        [
            Carrier(
                label: "valuePattern",
                file: try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOFile),
                image: try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machOImage),
                expected: GenericMetadataPatternProtocolBaseline.valuePattern
            ),
            Carrier(
                label: "classPattern",
                file: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOFile),
                image: try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machOImage),
                expected: GenericMetadataPatternProtocolBaseline.classPattern
            ),
        ]
    }

    @Test func hasExtraDataPattern() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.hasExtraDataPattern },
                image: { carrier.image.hasExtraDataPattern }
            )
            #expect(result == carrier.expected.hasExtraDataPattern, "\(carrier.label)")
        }
        // The two carriers differ here, which is what makes the trailing
        // arithmetic testable in both states.
        #expect(Set(try allCarriers().map(\.expected.hasExtraDataPattern)) == [false, true])
    }

    @Test func hasTrailingFlags() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.hasTrailingFlags },
                image: { carrier.image.hasTrailingFlags }
            )
            #expect(result == carrier.expected.hasTrailingFlags, "\(carrier.label)")
        }
    }

    @Test func partialPatternsOffset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.partialPatternsOffset },
                image: { carrier.image.partialPatternsOffset }
            )
            #expect(result == carrier.expected.partialPatternsOffset, "\(carrier.label)")
        }
    }

    @Test func size() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.size },
                image: { carrier.image.size }
            )
            #expect(result == carrier.expected.size, "\(carrier.label)")
        }
    }

    @Test func partialPatterns() async throws {
        for carrier in try allCarriers() {
            let offsets = try acrossAllReaders(
                file: { try carrier.file.partialPatterns(in: machOFile).map(\.offset) },
                image: { try carrier.image.partialPatterns(in: machOImage).map(\.offset) }
            )
            #expect(offsets.count == carrier.expected.partialPatternCount, "\(carrier.label)")
            #expect(offsets.first == (carrier.expected.partialPatternCount > 0 ? carrier.expected.partialPatternsOffset : nil), "\(carrier.label)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.partialPatterns(in: fileContext).map(\.offset) },
                image: { try carrier.image.partialPatterns(in: imageContext).map(\.offset) }
            )
            #expect(fromContext == offsets, "\(carrier.label)")
        }
    }

    @Test func extraDataPattern() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.extraDataPattern(in: machOFile)?.offset },
                image: { try carrier.image.extraDataPattern(in: machOImage)?.offset }
            )
            let expected = carrier.expected.hasExtraDataPattern ? carrier.expected.partialPatternsOffset : nil
            #expect(result == expected, "\(carrier.label)")
        }
    }
}
