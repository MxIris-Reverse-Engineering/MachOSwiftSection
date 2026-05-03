import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolConformanceDescriptor`.
///
/// `ProtocolConformanceDescriptor` is the raw section-level descriptor
/// pulled from `__swift5_proto`. Members covered (declared directly in
/// the file across the body and three same-file extensions):
///   - `offset`, `layout` — layout-trio storage.
///   - `typeReference` — computed property turning the layout's relative
///     offset + flag's `typeReferenceKind` into a `TypeReference` enum.
///   - `protocolDescriptor`, `resolvedTypeReference`, `witnessTablePattern`
///     — three reader overloads each (MachO + InProcess + ReadingContext)
///     collapsing to a single MethodKey under the scanner's name-based
///     deduplication.
///
/// Picker: the `Structs.StructTest: Protocols.ProtocolTest` conformance
/// — non-retroactive, no global-actor isolation, simplest path with a
/// resolvable witness table and a `directTypeDescriptor` type reference.
@Suite
final class ProtocolConformanceDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolConformanceDescriptor"
    static var registeredTestMethodNames: Set<String> {
        ProtocolConformanceDescriptorBaseline.registeredTestMethodNames
    }

    private func loadStructTestProtocolTestDescriptors() throws -> (file: ProtocolConformanceDescriptor, image: ProtocolConformanceDescriptor) {
        let fileConformance = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOFile)
        let imageConformance = try BaselineFixturePicker.protocolConformance_StructTestProtocolTest(in: machOImage)
        return (file: fileConformance.descriptor, image: imageConformance.descriptor)
    }

    @Test func offset() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()
        let flagsRawValue = try acrossAllReaders(
            file: { file.layout.flags.rawValue },
            image: { image.layout.flags.rawValue }
        )
        #expect(flagsRawValue == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.layoutFlagsRawValue)
    }

    /// `typeReference` is a computed property derived from
    /// `layout.flags.typeReferenceKind` + `layout.typeReference`.
    @Test func typeReference() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()
        let kindRawValue = try acrossAllReaders(
            file: { file.layout.flags.typeReferenceKind.rawValue },
            image: { image.layout.flags.typeReferenceKind.rawValue }
        )
        #expect(kindRawValue == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.typeReferenceKindRawValue)

        // The TypeReference enum case must match the kind.
        let fileTypeReference = file.typeReference
        if case .directTypeDescriptor = fileTypeReference {
            // Expected for StructTest: ProtocolTest.
        } else {
            Issue.record("Expected directTypeDescriptor for StructTest: ProtocolTest, got \(fileTypeReference)")
        }
    }

    /// `protocolDescriptor(in:)` is exposed in three overloads (MachO +
    /// in-process + ReadingContext) that all collapse to a single
    /// `MethodKey`. Exercise the MachO and ReadingContext overloads here.
    @Test func protocolDescriptor() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()
        let result = try acrossAllReaders(
            file: { (try file.protocolDescriptor(in: machOFile)) != nil },
            image: { (try image.protocolDescriptor(in: machOImage)) != nil }
        )
        #expect(result == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.hasProtocolDescriptor)

        // ReadingContext overload also exercised.
        let imageContextResult = (try image.protocolDescriptor(in: imageContext)) != nil
        #expect(imageContextResult == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.hasProtocolDescriptor)
    }

    /// `resolvedTypeReference(in:)` is exposed in three overloads (MachO +
    /// in-process + ReadingContext) that all collapse to a single
    /// `MethodKey`. Exercise the MachO and ReadingContext overloads here.
    @Test func resolvedTypeReference() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()

        let fileResolved = try file.resolvedTypeReference(in: machOFile)
        let imageResolved = try image.resolvedTypeReference(in: machOImage)
        let imageContextResolved = try image.resolvedTypeReference(in: imageContext)

        for (label, resolved) in [("file", fileResolved), ("image", imageResolved), ("imageContext", imageContextResolved)] {
            if case .directTypeDescriptor = resolved {
                // Expected.
            } else {
                Issue.record("\(label): Expected directTypeDescriptor for StructTest: ProtocolTest, got \(resolved)")
            }
        }
        #expect(ProtocolConformanceDescriptorBaseline.structTestProtocolTest.resolvedTypeReferenceIsDirectTypeDescriptor == true)
    }

    /// `witnessTablePattern(in:)` is exposed in three overloads (MachO +
    /// in-process + ReadingContext) that all collapse to a single
    /// `MethodKey`. Exercise the MachO and ReadingContext overloads here.
    @Test func witnessTablePattern() async throws {
        let (file, image) = try loadStructTestProtocolTestDescriptors()
        let result = try acrossAllReaders(
            file: { (try file.witnessTablePattern(in: machOFile)) != nil },
            image: { (try image.witnessTablePattern(in: machOImage)) != nil }
        )
        #expect(result == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.hasWitnessTablePattern)

        // ReadingContext overload also exercised.
        let imageContextResult = (try image.witnessTablePattern(in: imageContext)) != nil
        #expect(imageContextResult == ProtocolConformanceDescriptorBaseline.structTestProtocolTest.hasWitnessTablePattern)
    }
}
