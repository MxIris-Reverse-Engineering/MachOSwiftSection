import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class ContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func parent() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllContexts(fileDescriptor, imageDescriptor) { descriptor, context in
            (try descriptor.parent(in: context)) != nil
        }
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllContexts(fileDescriptor, imageDescriptor) { descriptor, context in
            (try descriptor.genericContext(in: context)) != nil
        }
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasGenericContext)
    }

    @Test func moduleContextDescriptor() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let presence = try acrossAllContexts(fileDescriptor, imageDescriptor) { descriptor, context in
            (try descriptor.moduleContextDescriptor(in: context)) != nil
        }
        #expect(presence == ContextDescriptorProtocolBaseline.structTest.hasModuleContextDescriptor)
    }

    @Test func isCImportedContextDescriptor() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllContexts(fileDescriptor, imageDescriptor) { descriptor, context in
            try descriptor.isCImportedContextDescriptor(in: context)
        }
        #expect(result == ContextDescriptorProtocolBaseline.structTest.isCImportedContextDescriptor)
    }

    @Test("subscript(dynamicMember:)") func subscriptDynamicMember() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // The dynamic-member subscript routes any `KeyPath<ContextDescriptorFlags, T>`
        // through `layout.flags`. Exercise the path by reading `kind` (a stable
        // scalar `ContextDescriptorKind`) via the dot-access syntax that triggers
        // dynamic-member lookup.
        let result = try acrossAllReaders(fileDescriptor, imageDescriptor) { $0.kind.rawValue }
        #expect(result == ContextDescriptorProtocolBaseline.structTest.subscriptKindRawValue)
    }
}
