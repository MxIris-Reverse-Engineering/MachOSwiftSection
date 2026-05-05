import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ContextDescriptorProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `parent`, `genericContext`, `moduleContextDescriptor`,
/// `isCImportedContextDescriptor`, and `subscript(dynamicMember:)` are all
/// owned by this Suite, NOT by the concrete-descriptor Suites.
///
/// Each `@Test` exercises the protocol-extension method through one of the
/// conforming concrete types (`Structs.StructTest`'s `StructDescriptor`).
/// Returned wrappers (`SymbolOrElement<ContextDescriptorWrapper>?`,
/// `GenericContext?`, etc.) aren't trivially Equatable, so we assert on
/// presence flags recorded in the baseline.
@Suite
final class ContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        ContextDescriptorProtocolBaseline.registeredTestMethodNames
    }

    @Test func parent() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllReaders(
            file: { (try fileDescriptor.parent(in: machOFile)) != nil },
            image: { (try imageDescriptor.parent(in: machOImage)) != nil }
        )
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageDescriptor.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextDescriptorProtocolBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllReaders(
            file: { (try fileDescriptor.genericContext(in: machOFile)) != nil },
            image: { (try imageDescriptor.genericContext(in: machOImage)) != nil }
        )
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageDescriptor.genericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextDescriptorProtocolBaseline.structTest.hasGenericContext)
    }

    @Test func moduleContextDescriptor() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllReaders(
            file: { (try fileDescriptor.moduleContextDescriptor(in: machOFile)) != nil },
            image: { (try imageDescriptor.moduleContextDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasModuleContextDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageDescriptor.moduleContextDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextDescriptorProtocolBaseline.structTest.hasModuleContextDescriptor)
    }

    @Test func isCImportedContextDescriptor() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllReaders(
            file: { try fileDescriptor.isCImportedContextDescriptor(in: machOFile) },
            image: { try imageDescriptor.isCImportedContextDescriptor(in: machOImage) }
        )
        #expect(result == ContextDescriptorProtocolBaseline.structTest.isCImportedContextDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxResult = try imageDescriptor.isCImportedContextDescriptor(in: imageContext)
        #expect(imageCtxResult == ContextDescriptorProtocolBaseline.structTest.isCImportedContextDescriptor)
    }

    @Test("subscript(dynamicMember:)") func subscriptDynamicMember() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // The dynamic-member subscript routes any `KeyPath<ContextDescriptorFlags, T>`
        // through `layout.flags`. Exercise the path by reading `kind` (a stable
        // scalar `ContextDescriptorKind`) via the dot-access syntax that triggers
        // dynamic-member lookup.
        let result = try acrossAllReaders(
            file: { fileDescriptor.kind.rawValue },
            image: { imageDescriptor.kind.rawValue }
        )
        #expect(result == ContextDescriptorProtocolBaseline.structTest.subscriptKindRawValue)
    }
}
