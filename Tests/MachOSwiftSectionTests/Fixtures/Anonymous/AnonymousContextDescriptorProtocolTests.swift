import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AnonymousContextDescriptorProtocol`.
///
/// The protocol provides the `mangledName(in:)` family of overloads (MachO,
/// InProcess, ReadingContext) plus the `hasMangledName` derived var.
/// The MangledName payload is a deep ABI tree we don't embed as a literal;
/// instead we verify cross-reader-consistent results at runtime.
@Suite
final class AnonymousContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnonymousContextDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        AnonymousContextDescriptorProtocolBaseline.registeredTestMethodNames
    }

    @Test func hasMangledName() async throws {
        let fileDescriptor = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)

        // `hasMangledName` is a pure-derivation getter on the protocol;
        // every reader must agree.
        let result = try acrossAllReaders(
            file: { fileDescriptor.hasMangledName },
            image: { imageDescriptor.hasMangledName }
        )
        // The presence flag's value is recorded against the same picker
        // (`anonymous_first`) on this Suite's own baseline.
        #expect(result == AnonymousContextDescriptorProtocolBaseline.firstAnonymous.hasMangledName)
    }

    @Test func mangledName() async throws {
        let fileDescriptor = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)

        // Cross-reader equality on the *presence* of the mangled name.
        // (The actual MangledName tree should also be Equatable, since
        // MangledName: Hashable, but we use presence-only here for parity
        // with the wrapper Suite and because the picker's first anonymous
        // context happens to have no mangled name in this fixture.)
        let filePresence = (try fileDescriptor.mangledName(in: machOFile)) != nil
        let imagePresence = (try imageDescriptor.mangledName(in: machOImage)) != nil
        let imageCtxPresence = (try imageDescriptor.mangledName(in: imageContext)) != nil

        #expect(filePresence == imagePresence)
        #expect(filePresence == imageCtxPresence)
        #expect(filePresence == AnonymousContextDescriptorProtocolBaseline.firstAnonymous.hasMangledName)
    }
}
