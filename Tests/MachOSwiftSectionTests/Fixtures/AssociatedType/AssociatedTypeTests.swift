import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AssociatedType` (the high-level wrapper around
/// `AssociatedTypeDescriptor`).
///
/// Each `@Test` exercises one ivar / initializer of `AssociatedType`. The
/// cross-reader assertions use cardinality (`records.count`) and presence
/// flags (`MangledName.elements.isEmpty`) — the underlying types
/// (`MangledName`, `[AssociatedTypeRecord]`) parse to deep ABI trees we
/// don't deep-compare; presence + cardinality is the meaningful invariant.
///
/// Picker: `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` conforming
/// to `AssociatedTypeWitnessPatterns.AssociatedPatternProtocol` (5 concrete
/// witnesses).
@Suite
final class AssociatedTypeTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AssociatedType"
    static var registeredTestMethodNames: Set<String> {
        AssociatedTypeBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadAssociatedTypes() throws -> (file: AssociatedType, image: AssociatedType) {
        let fileDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        let file = try AssociatedType(descriptor: fileDescriptor, in: machOFile)
        let image = try AssociatedType(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)

        let fileMachO = try AssociatedType(descriptor: fileDescriptor, in: machOFile)
        let imageMachO = try AssociatedType(descriptor: imageDescriptor, in: machOImage)
        let fileCtx = try AssociatedType(descriptor: fileDescriptor, in: fileContext)
        let imageCtx = try AssociatedType(descriptor: imageDescriptor, in: imageContext)

        #expect(fileMachO.descriptor.offset == AssociatedTypeBaseline.concreteWitnessTest.descriptorOffset)
        #expect(imageMachO.descriptor.offset == AssociatedTypeBaseline.concreteWitnessTest.descriptorOffset)
        #expect(fileCtx.descriptor.offset == AssociatedTypeBaseline.concreteWitnessTest.descriptorOffset)
        #expect(imageCtx.descriptor.offset == AssociatedTypeBaseline.concreteWitnessTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // The InProcess `init(descriptor:)` walks the descriptor via raw
        // pointer arithmetic; we just assert it succeeds and produces a
        // non-zero descriptor offset (the absolute pointer is per-process).
        let imageDescriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machOImage)
        let pointerWrapper = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcess = try AssociatedType(descriptor: pointerWrapper)
        #expect(inProcess.descriptor.offset != 0)
        #expect(inProcess.records.count == AssociatedTypeBaseline.concreteWitnessTest.recordsCount)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let associatedTypes = try loadAssociatedTypes()
        let result = try acrossAllReaders(
            file: { associatedTypes.file.descriptor.offset },
            image: { associatedTypes.image.descriptor.offset }
        )
        #expect(result == AssociatedTypeBaseline.concreteWitnessTest.descriptorOffset)
    }

    @Test func conformingTypeName() async throws {
        let associatedTypes = try loadAssociatedTypes()
        let presence = try acrossAllReaders(
            file: { !associatedTypes.file.conformingTypeName.elements.isEmpty },
            image: { !associatedTypes.image.conformingTypeName.elements.isEmpty }
        )
        #expect(presence == AssociatedTypeBaseline.concreteWitnessTest.hasConformingTypeName)
    }

    @Test func protocolTypeName() async throws {
        let associatedTypes = try loadAssociatedTypes()
        let presence = try acrossAllReaders(
            file: { !associatedTypes.file.protocolTypeName.elements.isEmpty },
            image: { !associatedTypes.image.protocolTypeName.elements.isEmpty }
        )
        #expect(presence == AssociatedTypeBaseline.concreteWitnessTest.hasProtocolTypeName)
    }

    @Test func records() async throws {
        let associatedTypes = try loadAssociatedTypes()
        let count = try acrossAllReaders(
            file: { associatedTypes.file.records.count },
            image: { associatedTypes.image.records.count }
        )
        #expect(count == AssociatedTypeBaseline.concreteWitnessTest.recordsCount)
    }
}
