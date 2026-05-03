import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AssociatedTypeDescriptor`.
///
/// Each `@Test` exercises one ivar / derived var / reader method declared
/// in `AssociatedTypeDescriptor.swift`. The cross-reader assertions use
/// counts/presence flags rather than full structural equality —
/// `MangledName` payloads parse to deep ABI trees that we don't deep-compare;
/// presence + cardinality is the meaningful invariant.
///
/// Picker: `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` conforming
/// to `AssociatedTypeWitnessPatterns.AssociatedPatternProtocol` (5 concrete
/// witnesses).
@Suite
final class AssociatedTypeDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AssociatedTypeDescriptor"
    static var registeredTestMethodNames: Set<String> {
        AssociatedTypeDescriptorBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadDescriptors() throws -> (file: AssociatedTypeDescriptor, image: AssociatedTypeDescriptor) {
        let file = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let image = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.offset },
            image: { descriptors.image.offset }
        )
        #expect(result == AssociatedTypeDescriptorBaseline.concreteWitnessTest.offset)
    }

    @Test func layout() async throws {
        // Cross-reader equality on the per-descriptor layout values.
        let descriptors = try loadDescriptors()
        let numAssociatedTypes = try acrossAllReaders(
            file: { descriptors.file.layout.numAssociatedTypes },
            image: { descriptors.image.layout.numAssociatedTypes }
        )
        #expect(numAssociatedTypes == AssociatedTypeDescriptorBaseline.concreteWitnessTest.layoutNumAssociatedTypes)

        let recordSize = try acrossAllReaders(
            file: { descriptors.file.layout.associatedTypeRecordSize },
            image: { descriptors.image.layout.associatedTypeRecordSize }
        )
        #expect(recordSize == AssociatedTypeDescriptorBaseline.concreteWitnessTest.layoutAssociatedTypeRecordSize)
    }

    // MARK: - TopLevelDescriptor conformance

    @Test func actualSize() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.actualSize },
            image: { descriptors.image.actualSize }
        )
        #expect(result == AssociatedTypeDescriptorBaseline.concreteWitnessTest.actualSize)
    }

    // MARK: - Reader methods

    @Test func conformingTypeName() async throws {
        let descriptors = try loadDescriptors()
        let presence = try acrossAllReaders(
            file: { (try? descriptors.file.conformingTypeName(in: machOFile)) != nil },
            image: { (try? descriptors.image.conformingTypeName(in: machOImage)) != nil }
        )
        #expect(presence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasConformingTypeName)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? descriptors.image.conformingTypeName(in: imageContext)) != nil
        #expect(imageCtxPresence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasConformingTypeName)
    }

    @Test func protocolTypeName() async throws {
        let descriptors = try loadDescriptors()
        let presence = try acrossAllReaders(
            file: { (try? descriptors.file.protocolTypeName(in: machOFile)) != nil },
            image: { (try? descriptors.image.protocolTypeName(in: machOImage)) != nil }
        )
        #expect(presence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasProtocolTypeName)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? descriptors.image.protocolTypeName(in: imageContext)) != nil
        #expect(imageCtxPresence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasProtocolTypeName)
    }

    @Test func associatedTypeRecords() async throws {
        let descriptors = try loadDescriptors()
        let count = try acrossAllReaders(
            file: { try descriptors.file.associatedTypeRecords(in: machOFile).count },
            image: { try descriptors.image.associatedTypeRecords(in: machOImage).count }
        )
        #expect(count == AssociatedTypeDescriptorBaseline.concreteWitnessTest.recordsCount)

        // ReadingContext-based overload also exercised.
        let imageCtxCount = try descriptors.image.associatedTypeRecords(in: imageContext).count
        #expect(imageCtxCount == AssociatedTypeDescriptorBaseline.concreteWitnessTest.recordsCount)
    }
}
