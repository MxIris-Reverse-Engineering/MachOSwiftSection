import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `Protocol` (the high-level wrapper around
/// `ProtocolDescriptor`).
///
/// Two pickers feed the assertions: `Protocols.ProtocolTest` (associated-
/// type protocol with one requirement-in-signature) and
/// `Protocols.ProtocolWitnessTableTest` (5 method requirements, no
/// requirement-in-signature).
@Suite
final class ProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Protocol"
    static var registeredTestMethodNames: Set<String> {
        ProtocolBaseline.registeredTestMethodNames
    }

    private func loadProtocolTestProtocols() throws -> (file: MachOSwiftSection.`Protocol`, image: MachOSwiftSection.`Protocol`) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOImage)
        let file = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let image = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    private func loadWitnessTableTestProtocols() throws -> (file: MachOSwiftSection.`Protocol`, image: MachOSwiftSection.`Protocol`) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let file = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let image = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Stored properties

    @Test func name() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.name },
            image: { image.name }
        )
        #expect(result == ProtocolBaseline.protocolTest.name)
    }

    @Test func descriptor() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.descriptor.offset },
            image: { image.descriptor.offset }
        )
        #expect(result == ProtocolBaseline.protocolTest.descriptorOffset)
    }

    @Test func protocolFlags() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.protocolFlags.rawValue },
            image: { image.protocolFlags.rawValue }
        )
        #expect(result == ProtocolBaseline.protocolTest.protocolFlagsRawValue)
    }

    @Test func baseRequirement() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.baseRequirement != nil },
            image: { image.baseRequirement != nil }
        )
        #expect(result == ProtocolBaseline.protocolTest.hasBaseRequirement)
    }

    @Test func requirementInSignatures() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.requirementInSignatures.count },
            image: { image.requirementInSignatures.count }
        )
        #expect(result == ProtocolBaseline.protocolTest.requirementInSignaturesCount)
    }

    @Test func requirements() async throws {
        let (file, image) = try loadWitnessTableTestProtocols()
        let result = try acrossAllReaders(
            file: { file.requirements.count },
            image: { image.requirements.count }
        )
        #expect(result == ProtocolBaseline.protocolWitnessTableTest.requirementsCount)
    }

    // MARK: - Derived counts

    @Test func numberOfRequirements() async throws {
        let (file, image) = try loadWitnessTableTestProtocols()
        let result = try acrossAllReaders(
            file: { file.numberOfRequirements },
            image: { image.numberOfRequirements }
        )
        #expect(result == ProtocolBaseline.protocolWitnessTableTest.numberOfRequirements)
    }

    @Test func numberOfRequirementsInSignature() async throws {
        let (file, image) = try loadProtocolTestProtocols()
        let result = try acrossAllReaders(
            file: { file.numberOfRequirementsInSignature },
            image: { image.numberOfRequirementsInSignature }
        )
        #expect(result == ProtocolBaseline.protocolTest.numberOfRequirementsInSignature)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithDescriptorAndMachO() async throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOFile)
        let protocolType = try MachOSwiftSection.`Protocol`(descriptor: descriptor, in: machOFile)
        #expect(protocolType.name == ProtocolBaseline.protocolTest.name)
        #expect(protocolType.descriptor.offset == ProtocolBaseline.protocolTest.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerWithDescriptor() async throws {
        // The descriptor-only init reads via `descriptor.asPointer` (in-process
        // pointer dereference, treating `offset` as the carrier pointer). It
        // requires the descriptor's `offset` to be a valid raw pointer
        // bit-pattern — true only if the descriptor was loaded via
        // `asPointerWrapper(in: machOImage)`, NOT via the section walk
        // (which carries offsets relative to the image base).
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let protocolType = try MachOSwiftSection.`Protocol`(descriptor: pointerDescriptor)
        #expect(protocolType.name == ProtocolBaseline.protocolTest.name)
        // The descriptor offset on a pointer-form wrapper is the raw pointer
        // bit-pattern, not the image-relative offset; validate the name
        // round-trip instead.
    }
}
