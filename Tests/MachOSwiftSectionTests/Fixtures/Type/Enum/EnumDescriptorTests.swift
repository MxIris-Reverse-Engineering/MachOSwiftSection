import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `EnumDescriptor`.
///
/// Members directly declared in `EnumDescriptor.swift` (across the body
/// and two same-file extensions). Protocol-extension methods that
/// surface here at compile-time — `name(in:)`, `fields(in:)`, etc. —
/// live on `TypeContextDescriptorProtocol` and are exercised in Task 9
/// under `TypeContextDescriptorProtocolTests`.
///
/// Three pickers feed the assertions so each predicate's true branch is
/// witnessed by at least one entry:
///   - `Enums.NoPayloadEnumTest` — the all-empty-cases path (4 cases,
///     `numberOfPayloadCases == 0`)
///   - `Enums.SinglePayloadEnumTest` — the canonical `isSinglePayload` path
///     (`case value(String)` + 2 empty cases)
///   - `Enums.MultiPayloadEnumTests` — the canonical `isMultiPayload` path
///     (3 payload cases + 1 empty)
@Suite
final class EnumDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "EnumDescriptor"
    static var registeredTestMethodNames: Set<String> {
        EnumDescriptorBaseline.registeredTestMethodNames
    }

    private func loadNoPayloadDescriptors() throws -> (file: EnumDescriptor, image: EnumDescriptor) {
        let file = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOFile)
        let image = try BaselineFixturePicker.enum_NoPayloadEnumTest(in: machOImage)
        return (file: file, image: image)
    }

    private func loadSinglePayloadDescriptors() throws -> (file: EnumDescriptor, image: EnumDescriptor) {
        let file = try BaselineFixturePicker.enum_SinglePayloadEnumTest(in: machOFile)
        let image = try BaselineFixturePicker.enum_SinglePayloadEnumTest(in: machOImage)
        return (file: file, image: image)
    }

    private func loadMultiPayloadDescriptors() throws -> (file: EnumDescriptor, image: EnumDescriptor) {
        let file = try BaselineFixturePicker.enum_MultiPayloadEnumTest(in: machOFile)
        let image = try BaselineFixturePicker.enum_MultiPayloadEnumTest(in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Layout / offset (NoPayloadEnumTest)

    @Test func offset() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let numPayloadCasesAndPayloadSizeOffset = try acrossAllReaders(
            file: { fileSubject.layout.numPayloadCasesAndPayloadSizeOffset },
            image: { imageSubject.layout.numPayloadCasesAndPayloadSizeOffset }
        )
        let numEmptyCases = try acrossAllReaders(
            file: { fileSubject.layout.numEmptyCases },
            image: { imageSubject.layout.numEmptyCases }
        )
        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )
        #expect(numPayloadCasesAndPayloadSizeOffset == EnumDescriptorBaseline.noPayloadEnumTest.layoutNumPayloadCasesAndPayloadSizeOffset)
        #expect(numEmptyCases == EnumDescriptorBaseline.noPayloadEnumTest.layoutNumEmptyCases)
        #expect(flagsRaw == EnumDescriptorBaseline.noPayloadEnumTest.layoutFlagsRawValue)
    }

    // MARK: - Case-count accessors (NoPayloadEnumTest)

    @Test func numberOfCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.numberOfCases },
            image: { imageSubject.numberOfCases }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfCases)
    }

    @Test func numberOfEmptyCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.numberOfEmptyCases },
            image: { imageSubject.numberOfEmptyCases }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfEmptyCases)
    }

    @Test func numberOfPayloadCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.numberOfPayloadCases },
            image: { imageSubject.numberOfPayloadCases }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfPayloadCases)
    }

    // MARK: - Payload-size accessors (NoPayloadEnumTest — both fields zero)

    @Test func hasPayloadSizeOffset() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasPayloadSizeOffset },
            image: { imageSubject.hasPayloadSizeOffset }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.hasPayloadSizeOffset)
    }

    @Test func payloadSizeOffset() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.payloadSizeOffset },
            image: { imageSubject.payloadSizeOffset }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.payloadSizeOffset)
    }

    // MARK: - Predicate family (each branch witnessed by the right picker)

    /// Witnessed by `NoPayloadEnumTest`: false (4 cases, not 1).
    @Test func isSingleEmptyCaseOnly() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isSingleEmptyCaseOnly },
            image: { imageSubject.isSingleEmptyCaseOnly }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.isSingleEmptyCaseOnly)
    }

    /// Witnessed by `NoPayloadEnumTest`: false (no payload case).
    @Test func isSinglePayloadCaseOnly() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isSinglePayloadCaseOnly },
            image: { imageSubject.isSinglePayloadCaseOnly }
        )
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.isSinglePayloadCaseOnly)
    }

    /// Witnessed by `SinglePayloadEnumTest`: 1 payload + 2 empty = `true`.
    @Test func isSinglePayload() async throws {
        let (fileSubject, imageSubject) = try loadSinglePayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isSinglePayload },
            image: { imageSubject.isSinglePayload }
        )
        #expect(result == EnumDescriptorBaseline.singlePayloadEnumTest.isSinglePayload)
    }

    /// Witnessed by `MultiPayloadEnumTests`: 3 payloads + 1 empty = `true`.
    @Test func isMultiPayload() async throws {
        let (fileSubject, imageSubject) = try loadMultiPayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.isMultiPayload },
            image: { imageSubject.isMultiPayload }
        )
        #expect(result == EnumDescriptorBaseline.multiPayloadEnumTest.isMultiPayload)
    }

    /// Witnessed by `SinglePayloadEnumTest`: at least one payload case.
    @Test func hasPayloadCases() async throws {
        let (fileSubject, imageSubject) = try loadSinglePayloadDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasPayloadCases },
            image: { imageSubject.hasPayloadCases }
        )
        #expect(result == EnumDescriptorBaseline.singlePayloadEnumTest.hasPayloadCases)
    }
}
