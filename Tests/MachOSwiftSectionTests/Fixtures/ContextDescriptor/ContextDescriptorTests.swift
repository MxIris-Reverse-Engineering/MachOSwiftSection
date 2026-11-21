import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ContextDescriptor`.
///
/// `ContextDescriptor` is the bare 8-byte header (`flags + parent`) shared
/// by every kind of context descriptor. It declares only `offset` and
/// `layout` directly (`init(layout:offset:)` is filtered as memberwise-
/// synthesized). Protocol-extension members (`parent`, `genericContext`,
/// `subscript(dynamicMember:)`, etc.) live on `ContextDescriptorProtocol`
/// and are covered by `ContextDescriptorProtocolTests`.
///
/// We materialize a `ContextDescriptor` by reading the bare header at the
/// offset of `Structs.StructTest` (the same path `ContextDescriptorWrapper.resolve`
/// uses to dispatch on the `kind` byte).
@Suite
@FixtureSuite
final class ContextDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: read the bare `ContextDescriptor` header at the
    /// `Structs.StructTest` offset against both readers.
    private func loadStructTestContextDescriptors() throws -> (file: ContextDescriptor, image: ContextDescriptor) {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file: ContextDescriptor = try machOFile.readWrapperElement(offset: fileSubject.offset)
        let image: ContextDescriptor = try machOImage.readWrapperElement(offset: imageSubject.offset)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let descriptors = try loadStructTestContextDescriptors()
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.offset }
        #expect(result == ContextDescriptorBaseline.structTest.offset)
    }

    @Test func layout() async throws {
        let descriptors = try loadStructTestContextDescriptors()
        // Cross-reader equality on the only stable scalar field
        // (`flags.rawValue`); `parent` is a relative pointer whose value
        // varies by reader.
        let flagsRaw = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.flags.rawValue }
        #expect(flagsRaw == ContextDescriptorBaseline.structTest.layoutFlagsRawValue)
    }
}
