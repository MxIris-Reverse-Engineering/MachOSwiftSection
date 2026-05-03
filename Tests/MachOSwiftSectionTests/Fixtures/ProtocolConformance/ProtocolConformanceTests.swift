import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolConformance`.
///
/// `ProtocolConformance` is the high-level wrapper around
/// `ProtocolConformanceDescriptor`. The init eagerly materializes the
/// descriptor's protocol/typeReference/witnessTablePattern plus the
/// trailing-objects payload (retroactiveContextDescriptor / conditional
/// requirements / pack shape descriptors / resilient witnesses /
/// generic witness table / global actor reference) gated on the flag bits.
///
/// Four pickers feed the assertions so each trailing-object branch is
/// witnessed:
///   - `Structs.StructTest: Protocols.ProtocolTest` — simplest path
///     (no resilient witnesses, no conditional reqs, no global actor).
///   - The first conditional conformance — surfaces
///     `conditionalRequirements`.
///   - The first global-actor-isolated conformance — surfaces
///     `globalActorReference`.
///   - The first resilient-witness conformance — surfaces
///     `resilientWitnessesHeader` and `resilientWitnesses`.
@Suite
final class ProtocolConformanceTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolConformance"
    static var registeredTestMethodNames: Set<String> {
        ProtocolConformanceBaseline.registeredTestMethodNames
    }

    private func loadStructTestProtocolTest() throws -> (file: ProtocolConformance, image: ProtocolConformance) {
        let file = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOFile)
        let image = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOImage)
        return (file: file, image: image)
    }

    private func loadConditionalFirst() throws -> (file: ProtocolConformance, image: ProtocolConformance) {
        let file = try BaselineFixturePicker.protocolConformance_conditionalFirst(in: machOFile)
        let image = try BaselineFixturePicker.protocolConformance_conditionalFirst(in: machOImage)
        return (file: file, image: image)
    }

    private func loadGlobalActorFirst() throws -> (file: ProtocolConformance, image: ProtocolConformance) {
        let file = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOFile)
        let image = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOImage)
        return (file: file, image: image)
    }

    private func loadResilientFirst() throws -> (file: ProtocolConformance, image: ProtocolConformance) {
        let file = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOFile)
        let image = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Stored properties (StructTest: ProtocolTest baseline)

    @Test func descriptor() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.descriptor.offset },
            image: { image.descriptor.offset }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.descriptorOffset)
    }

    @Test func flags() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.flags.rawValue },
            image: { image.flags.rawValue }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.flagsRawValue)
    }

    @Test("protocol") func conformedProtocol() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.protocol != nil },
            image: { image.protocol != nil }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.hasProtocol)
    }

    @Test func typeReference() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        // Both readers must agree on the case (directTypeDescriptor for
        // StructTest: ProtocolTest).
        let fileTypeReference = file.typeReference
        let imageTypeReference = image.typeReference
        for (label, ref) in [("file", fileTypeReference), ("image", imageTypeReference)] {
            if case .directTypeDescriptor = ref {
                // Expected.
            } else {
                Issue.record("\(label): Expected directTypeDescriptor for StructTest: ProtocolTest, got \(ref)")
            }
        }
    }

    @Test func witnessTablePattern() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.witnessTablePattern != nil },
            image: { image.witnessTablePattern != nil }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.hasWitnessTablePattern)
    }

    @Test func retroactiveContextDescriptor() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.retroactiveContextDescriptor != nil },
            image: { image.retroactiveContextDescriptor != nil }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.hasRetroactiveContextDescriptor)
    }

    // MARK: - Trailing-object branches (per-fixture variants)

    @Test func conditionalRequirements() async throws {
        let (file, image) = try loadConditionalFirst()
        let result = try acrossAllReaders(
            file: { file.conditionalRequirements.count },
            image: { image.conditionalRequirements.count }
        )
        #expect(result == ProtocolConformanceBaseline.conditionalFirst.conditionalRequirementsCount)
    }

    @Test func conditionalPackShapeDescriptors() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.conditionalPackShapeDescriptors.count },
            image: { image.conditionalPackShapeDescriptors.count }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.conditionalPackShapeDescriptorsCount)
    }

    @Test func resilientWitnessesHeader() async throws {
        let (file, image) = try loadResilientFirst()
        let result = try acrossAllReaders(
            file: { file.resilientWitnessesHeader != nil },
            image: { image.resilientWitnessesHeader != nil }
        )
        #expect(result == ProtocolConformanceBaseline.resilientFirst.hasResilientWitnessesHeader)
    }

    @Test func resilientWitnesses() async throws {
        let (file, image) = try loadResilientFirst()
        let result = try acrossAllReaders(
            file: { file.resilientWitnesses.count },
            image: { image.resilientWitnesses.count }
        )
        #expect(result == ProtocolConformanceBaseline.resilientFirst.resilientWitnessesCount)
    }

    @Test func genericWitnessTable() async throws {
        let (file, image) = try loadStructTestProtocolTest()
        let result = try acrossAllReaders(
            file: { file.genericWitnessTable != nil },
            image: { image.genericWitnessTable != nil }
        )
        #expect(result == ProtocolConformanceBaseline.structTestProtocolTest.hasGenericWitnessTable)
    }

    @Test func globalActorReference() async throws {
        let (file, image) = try loadGlobalActorFirst()
        let result = try acrossAllReaders(
            file: { file.globalActorReference != nil },
            image: { image.globalActorReference != nil }
        )
        #expect(result == ProtocolConformanceBaseline.globalActorFirst.hasGlobalActorReference)
    }

    // MARK: - Initializers

    /// `init(descriptor:in:)` collapses across MachO and ReadingContext
    /// overloads under PublicMemberScanner's name-based deduplication.
    /// Exercise both reader paths here.
    @Test("init(descriptor:in:)") func initializerWithDescriptorAndMachO() async throws {
        let descriptor = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOFile).descriptor
        let conformance = try ProtocolConformance(descriptor: descriptor, in: machOFile)
        #expect(conformance.descriptor.offset == ProtocolConformanceBaseline.structTestProtocolTest.descriptorOffset)
        #expect(conformance.flags.rawValue == ProtocolConformanceBaseline.structTestProtocolTest.flagsRawValue)

        // ReadingContext overload also exercised (collapsed to the same
        // MethodKey in the scanner).
        let imageDescriptor = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOImage).descriptor
        let imageConformance = try ProtocolConformance(descriptor: imageDescriptor, in: imageContext)
        #expect(imageConformance.descriptor.offset == ProtocolConformanceBaseline.structTestProtocolTest.descriptorOffset)
    }

    /// `init(descriptor:)` reads via `descriptor.asPointer` (in-process
    /// pointer dereference). It requires the descriptor's `offset` to be
    /// a valid raw pointer bit-pattern — true only if the descriptor
    /// was loaded via `asPointerWrapper(in: machOImage)`, NOT via the
    /// section walk (which carries offsets relative to the image base).
    @Test("init(descriptor:)") func initializerWithDescriptor() async throws {
        let imageDescriptor = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOImage).descriptor
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let conformance = try ProtocolConformance(descriptor: pointerDescriptor)
        #expect(conformance.flags.rawValue == ProtocolConformanceBaseline.structTestProtocolTest.flagsRawValue)
        #expect(conformance.protocol != nil)
    }
}
