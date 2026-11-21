import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ProtocolDescriptor`.
///
/// Members directly declared in `ProtocolDescriptor.swift` (across the
/// body and three same-file extensions). Protocol-extension methods that
/// surface here at compile-time — `name(in:)`, `mangledName(in:)` — live
/// on `NamedContextDescriptorProtocol` and are exercised in Task 6 under
/// `NamedContextDescriptorProtocolTests`.
@Suite
@FixtureSuite
final class ProtocolDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadProtocolTestDescriptors() throws -> (file: ProtocolDescriptor, image: ProtocolDescriptor) {
        let file = try BaselineFixturePicker.protocol_ProtocolTest(in: machOFile)
        let image = try BaselineFixturePicker.protocol_ProtocolTest(in: machOImage)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let result = try acrossAllReaders(file, image) { $0.offset }
        #expect(result == ProtocolDescriptorBaseline.protocolTest.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let numRequirementsInSignature = try acrossAllReaders(file, image) { $0.layout.numRequirementsInSignature }
        let numRequirements = try acrossAllReaders(file, image) { $0.layout.numRequirements }
        let flagsRaw = try acrossAllReaders(file, image) { $0.layout.flags.rawValue }

        #expect(numRequirementsInSignature == ProtocolDescriptorBaseline.protocolTest.layoutNumRequirementsInSignature)
        #expect(numRequirements == ProtocolDescriptorBaseline.protocolTest.layoutNumRequirements)
        #expect(flagsRaw == ProtocolDescriptorBaseline.protocolTest.layoutFlagsRawValue)
    }

    /// `associatedTypes(in:)` is exposed in three overloads (MachO +
    /// in-process + ReadingContext) that all collapse to a single
    /// `MethodKey` under PublicMemberScanner's name-based key. Exercise
    /// the ReadingContext overload over both readers here.
    @Test func associatedTypes() async throws {
        let (file, image) = try loadProtocolTestDescriptors()
        let result = try acrossAllContexts(file, image) { descriptor, context in try descriptor.associatedTypes(in: context) }
        #expect(result == ProtocolDescriptorBaseline.protocolTest.associatedTypes)
    }
}
