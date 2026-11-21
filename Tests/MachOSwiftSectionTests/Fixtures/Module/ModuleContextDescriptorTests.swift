import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ModuleContextDescriptor`.
///
/// `ModuleContextDescriptor` declares only `offset` and `layout` directly
/// (`init(layout:offset:)` is filtered as memberwise-synthesized). The
/// `name(in:)` accessor lives on `NamedContextDescriptorProtocol`; that
/// surface is exercised through the wrapper Suite (`ModuleContextTests`)
/// to avoid duplicating coverage here.
@Suite
@FixtureSuite
final class ModuleContextDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)

        let result = try acrossAllReaders(fileSubject, imageSubject) { $0.offset }
        #expect(result == ModuleContextDescriptorBaseline.symbolTestsCore.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageSubject = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)

        let flagsRaw = try acrossAllReaders(fileSubject, imageSubject) { $0.layout.flags.rawValue }
        #expect(flagsRaw == ModuleContextDescriptorBaseline.symbolTestsCore.layoutFlagsRawValue)
    }
}
