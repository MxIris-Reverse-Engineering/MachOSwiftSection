import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolDescriptor`.
///
/// Members directly declared in `ProtocolDescriptor.swift` (across the
/// body and three same-file extensions). Protocol-extension methods that
/// surface here at compile-time — `name(in:)`, `mangledName(in:)` — live
/// on `NamedContextDescriptorProtocol` and are exercised in Task 6 under
/// `NamedContextDescriptorProtocolTests`.
@Suite
final class ProtocolDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolDescriptor"
    static var registeredTestMethodNames: Set<String> {
        ProtocolDescriptorBaseline.registeredTestMethodNames
    }

    private func loadProtocolTestDescriptors() throws -> (file: ProtocolDescriptor, image: ProtocolDescriptor) {
        let file = try BaselineFixturePicker.protocol_ProtocolTest(in: machOFile)
        let image = try BaselineFixturePicker.protocol_ProtocolTest(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolDescriptorBaseline.protocolTest.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let numRequirementsInSignature = try acrossAllReaders(
            file: { file.layout.numRequirementsInSignature },
            image: { image.layout.numRequirementsInSignature }
        )
        let numRequirements = try acrossAllReaders(
            file: { file.layout.numRequirements },
            image: { image.layout.numRequirements }
        )
        let flagsRaw = try acrossAllReaders(
            file: { file.layout.flags.rawValue },
            image: { image.layout.flags.rawValue }
        )

        #expect(numRequirementsInSignature == ProtocolDescriptorBaseline.protocolTest.layoutNumRequirementsInSignature)
        #expect(numRequirements == ProtocolDescriptorBaseline.protocolTest.layoutNumRequirements)
        #expect(flagsRaw == ProtocolDescriptorBaseline.protocolTest.layoutFlagsRawValue)
    }

    /// `associatedTypes(in:)` is exposed in three overloads (MachO +
    /// in-process + ReadingContext) that all collapse to a single
    /// `MethodKey` under PublicMemberScanner's name-based key. Exercise
    /// the MachO and ReadingContext overloads here.
    @Test func associatedTypes() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let result = try acrossAllReaders(
            file: { try file.associatedTypes(in: machOFile) },
            image: { try image.associatedTypes(in: machOImage) }
        )
        #expect(result == ProtocolDescriptorBaseline.protocolTest.associatedTypes)

        // ReadingContext overload also exercised.
        let imageContextResult = try image.associatedTypes(in: imageContext)
        #expect(imageContextResult == ProtocolDescriptorBaseline.protocolTest.associatedTypes)
    }
}
