import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolRequirement`.
///
/// Picker: `Protocols.ProtocolWitnessTableTest` — its 5 method
/// requirements (`a`/`b`/`c`/`d`/`e`) flesh out the trailing array; we
/// pick the first requirement and exercise its accessors. None of them has
/// a default implementation, so the default-implementation accessors are
/// ALSO exercised on `DefaultImplementationVariants.BasicDefaultProtocol`'s
/// first defaulted requirement — a `nil == nil` on the first picker alone
/// never ran the relative-pointer arithmetic.
///
/// `ProtocolBaseRequirement` (the second struct in the same file) gets
/// its own Suite (`ProtocolBaseRequirementTests`).
@Suite
final class ProtocolRequirementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolRequirement"
    static var registeredTestMethodNames: Set<String> {
        ProtocolRequirementBaseline.registeredTestMethodNames
    }

    private func loadFirstRequirements() throws -> (file: ProtocolRequirement, image: ProtocolRequirement) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        let file = try required(fileProtocol.requirements.first)
        let image = try required(imageProtocol.requirements.first)
        return (file: file, image: image)
    }

    private func loadFirstDefaultedRequirements() throws -> (file: ProtocolRequirement, image: ProtocolRequirement) {
        let fileDescriptor = try BaselineFixturePicker.protocol_BasicDefaultProtocol(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_BasicDefaultProtocol(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        let file = try required(fileProtocol.requirements.first { $0.layout.defaultImplementation.isValid })
        let image = try required(imageProtocol.requirements.first { $0.layout.defaultImplementation.isValid })
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolRequirementBaseline.firstRequirement.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { file.layout.flags.rawValue },
            image: { image.layout.flags.rawValue }
        )
        #expect(result == ProtocolRequirementBaseline.firstRequirement.layoutFlagsRawValue)
    }

    /// `defaultImplementationOffset` is pure relative-pointer arithmetic:
    /// pinned as a literal — `nil` for a requirement without a default, a
    /// real offset for a defaulted one — and identical across readers.
    @Test func defaultImplementationOffset() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { file.defaultImplementationOffset },
            image: { image.defaultImplementationOffset }
        )
        #expect(result == nil)
        #expect(result == ProtocolRequirementBaseline.firstRequirement.defaultImplementationOffset)

        let (defaultedFile, defaultedImage) = try loadFirstDefaultedRequirements()
        let defaultedResult = try acrossAllReaders(
            file: { defaultedFile.defaultImplementationOffset },
            image: { defaultedImage.defaultImplementationOffset }
        )
        #expect(defaultedResult != nil)
        #expect(defaultedResult == ProtocolRequirementBaseline.firstDefaultedRequirement.defaultImplementationOffset)
        // The literal is the resolved target, never the pointer field's own
        // position: an implementation that returned `offset(of:)` instead of
        // resolving through it would land exactly there.
        #expect(defaultedResult != defaultedFile.offset(of: \.defaultImplementation))
    }

    /// The `ReadingContext` leg reports the same location as a context
    /// address (a file offset for `MachOContext`), `nil` included.
    @Test func defaultImplementationAddress() async throws {
        let (file, image) = try loadFirstRequirements()
        let fileAddress = try file.defaultImplementationAddress(in: fileContext)
        let imageAddress = try image.defaultImplementationAddress(in: imageContext)
        #expect(fileAddress == nil)
        #expect(imageAddress == nil)

        let (defaultedFile, defaultedImage) = try loadFirstDefaultedRequirements()
        let defaultedFileAddress = try defaultedFile.defaultImplementationAddress(in: fileContext)
        let defaultedImageAddress = try defaultedImage.defaultImplementationAddress(in: imageContext)
        #expect(defaultedFileAddress != nil)
        #expect(defaultedFileAddress == defaultedFile.defaultImplementationOffset)
        #expect(defaultedImageAddress == defaultedImage.defaultImplementationOffset)
        #expect(defaultedImageAddress == ProtocolRequirementBaseline.firstDefaultedRequirement.defaultImplementationOffset)
    }
}
