import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class EnumDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
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
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.offset }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.offset)
    }

    @Test func layout() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let numPayloadCasesAndPayloadSizeOffset = try acrossAllReaders(fileSubject, imageSubject) { descriptor in
            descriptor.layout.numPayloadCasesAndPayloadSizeOffset
        }
        let numEmptyCases = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.numEmptyCases }
        let flagsRaw = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.flags.rawValue }
        #expect(numPayloadCasesAndPayloadSizeOffset == EnumDescriptorBaseline.noPayloadEnumTest.layoutNumPayloadCasesAndPayloadSizeOffset)
        #expect(numEmptyCases == EnumDescriptorBaseline.noPayloadEnumTest.layoutNumEmptyCases)
        #expect(flagsRaw == EnumDescriptorBaseline.noPayloadEnumTest.layoutFlagsRawValue)
    }

    // MARK: - Case-count accessors (NoPayloadEnumTest)

    @Test func numberOfCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.numberOfCases }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfCases)
    }

    @Test func numberOfEmptyCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.numberOfEmptyCases }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfEmptyCases)
    }

    @Test func numberOfPayloadCases() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.numberOfPayloadCases }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.numberOfPayloadCases)
    }

    // MARK: - Payload-size accessors (NoPayloadEnumTest — both fields zero)

    @Test func hasPayloadSizeOffset() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasPayloadSizeOffset }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.hasPayloadSizeOffset)
    }

    @Test func payloadSizeOffset() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.payloadSizeOffset }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.payloadSizeOffset)
    }

    // MARK: - Predicate family (each branch witnessed by the right picker)

    /// Witnessed by `NoPayloadEnumTest`: false (4 cases, not 1).
    @Test func isSingleEmptyCaseOnly() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isSingleEmptyCaseOnly }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.isSingleEmptyCaseOnly)
    }

    /// Witnessed by `NoPayloadEnumTest`: false (no payload case).
    @Test func isSinglePayloadCaseOnly() async throws {
        let (fileSubject, imageSubject) = try loadNoPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isSinglePayloadCaseOnly }
        #expect(result == EnumDescriptorBaseline.noPayloadEnumTest.isSinglePayloadCaseOnly)
    }

    /// Witnessed by `SinglePayloadEnumTest`: 1 payload + 2 empty = `true`.
    @Test func isSinglePayload() async throws {
        let (fileSubject, imageSubject) = try loadSinglePayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isSinglePayload }
        #expect(result == EnumDescriptorBaseline.singlePayloadEnumTest.isSinglePayload)
    }

    /// Witnessed by `MultiPayloadEnumTests`: 3 payloads + 1 empty = `true`.
    @Test func isMultiPayload() async throws {
        let (fileSubject, imageSubject) = try loadMultiPayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.isMultiPayload }
        #expect(result == EnumDescriptorBaseline.multiPayloadEnumTest.isMultiPayload)
    }

    /// Witnessed by `SinglePayloadEnumTest`: at least one payload case.
    @Test func hasPayloadCases() async throws {
        let (fileSubject, imageSubject) = try loadSinglePayloadDescriptors()
        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.hasPayloadCases }
        #expect(result == EnumDescriptorBaseline.singlePayloadEnumTest.hasPayloadCases)
    }
}
