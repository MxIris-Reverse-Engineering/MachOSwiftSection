import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ModuleContextDescriptor`.
///
/// `ModuleContextDescriptor` declares only `offset` and `layout` directly
/// (`init(layout:offset:)` is filtered as memberwise-synthesized). The
/// `name(in:)` accessor lives on `NamedContextDescriptorProtocol`; that
/// surface is exercised through the wrapper Suite (`ModuleContextTests`)
/// to avoid duplicating coverage here.
@Suite
final class ModuleContextDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ModuleContextDescriptor"
    static var registeredTestMethodNames: Set<String> {
        ModuleContextDescriptorBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)

        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == ModuleContextDescriptorBaseline.symbolTestsCore.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)

        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )
        #expect(flagsRaw == ModuleContextDescriptorBaseline.symbolTestsCore.layoutFlagsRawValue)
    }
}
