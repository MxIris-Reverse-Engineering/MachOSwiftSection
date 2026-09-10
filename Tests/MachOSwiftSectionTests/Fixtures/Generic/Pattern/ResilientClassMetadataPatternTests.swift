import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ResilientClassMetadataPattern`.
///
/// The carrier is `ResilientClassFixtures.ResilientChild`, a NON-generic
/// class whose superclass lives in another resilience domain. Its pattern is
/// reached through the singleton metadata initialization record's union
/// field, not through a generic context — that route is what this Suite
/// exercises end to end.
@Suite
final class ResilientClassMetadataPatternTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ResilientClassMetadataPattern"
    static var registeredTestMethodNames: Set<String> {
        ResilientClassMetadataPatternBaseline.registeredTestMethodNames
    }

    private func loadPatterns() throws -> (file: ResilientClassMetadataPattern, image: ResilientClassMetadataPattern) {
        (
            file: try BaselineFixturePicker.resilientClassMetadataPattern_resilientChild(in: machOFile),
            image: try BaselineFixturePicker.resilientClassMetadataPattern_resilientChild(in: machOImage)
        )
    }

    @Test func offset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.offset },
            image: { patterns.image.offset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.offset)

        // The pattern is reached through the singleton record's union field,
        // which is the whole point of this carrier.
        let descriptor = try BaselineFixturePicker.class_ResilientChild(in: machOFile)
        let resilientChild = try Class(descriptor: descriptor, in: machOFile)
        let initialization = try required(resilientChild.singletonMetadataInitialization)
        #expect(initialization.resilientClassPatternOffset == result)
        #expect(descriptor.hasResilientSuperclass, "the union field only holds a pattern for a resilient-superclass class")
    }

    @Test func layout() async throws {
        let patterns = try loadPatterns()
        let classFlags = try acrossAllReaders(
            file: { patterns.file.layout.classFlags },
            image: { patterns.image.layout.classFlags }
        )
        #expect(classFlags == ResilientClassMetadataPatternBaseline.classFlags)
        // Three function pointers, the class flag word and two interop
        // pointers.
        #expect(MemoryLayout<ResilientClassMetadataPattern.Layout>.size == 24)
    }

    @Test func classFlags() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.classFlags },
            image: { patterns.image.classFlags }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.classFlags)
    }

    /// Null here is meaningful, not missing data: it tells the runtime to
    /// call `swift_relocateClassMetadata` with this pattern instead.
    @Test func relocationFunctionOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.relocationFunctionOffset },
            image: { patterns.image.relocationFunctionOffset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.relocationFunctionOffset)
    }

    @Test func destroyOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.destroyOffset },
            image: { patterns.image.destroyOffset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.destroyOffset)
    }

    @Test func instanceVariableDestroyerOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.instanceVariableDestroyerOffset },
            image: { patterns.image.instanceVariableDestroyerOffset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.instanceVariableDestroyerOffset)
    }

    @Test func dataOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.dataOffset },
            image: { patterns.image.dataOffset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.dataOffset)
    }

    @Test func metaclassOffset() async throws {
        let patterns = try loadPatterns()
        let result = try acrossAllReaders(
            file: { patterns.file.metaclassOffset },
            image: { patterns.image.metaclassOffset }
        )
        #expect(result == ResilientClassMetadataPatternBaseline.metaclassOffset)
    }
}
