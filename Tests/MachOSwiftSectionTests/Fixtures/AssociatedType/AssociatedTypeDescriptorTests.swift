import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class AssociatedTypeDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    // MARK: - Helpers

    private func loadDescriptors() throws -> (file: AssociatedTypeDescriptor, image: AssociatedTypeDescriptor) {
        let file = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let image = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.offset }
        #expect(result == AssociatedTypeDescriptorBaseline.concreteWitnessTest.offset)
    }

    @Test func layout() async throws {
        // Cross-reader equality on the per-descriptor layout values.
        let descriptors = try loadDescriptors()
        let numAssociatedTypes = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.numAssociatedTypes }
        #expect(numAssociatedTypes == AssociatedTypeDescriptorBaseline.concreteWitnessTest.layoutNumAssociatedTypes)

        let recordSize = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.associatedTypeRecordSize }
        #expect(recordSize == AssociatedTypeDescriptorBaseline.concreteWitnessTest.layoutAssociatedTypeRecordSize)
    }

    // MARK: - TopLevelDescriptor conformance

    @Test func actualSize() async throws {
        let descriptors = try loadDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.actualSize }
        #expect(result == AssociatedTypeDescriptorBaseline.concreteWitnessTest.actualSize)
    }

    // MARK: - Reader methods

    @Test func conformingTypeName() async throws {
        let descriptors = try loadDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try? descriptor.conformingTypeName(in: context)) != nil
        }
        #expect(presence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasConformingTypeName)
    }

    @Test func protocolTypeName() async throws {
        let descriptors = try loadDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try? descriptor.protocolTypeName(in: context)) != nil
        }
        #expect(presence == AssociatedTypeDescriptorBaseline.concreteWitnessTest.hasProtocolTypeName)
    }

    @Test func associatedTypeRecords() async throws {
        let descriptors = try loadDescriptors()
        let count = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            try descriptor.associatedTypeRecords(in: context).count
        }
        #expect(count == AssociatedTypeDescriptorBaseline.concreteWitnessTest.recordsCount)
    }
}
