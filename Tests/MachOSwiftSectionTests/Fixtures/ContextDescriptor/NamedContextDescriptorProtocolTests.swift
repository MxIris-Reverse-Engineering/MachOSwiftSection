import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `NamedContextDescriptorProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `name(in:)` and `mangledName(in:)` are declared in
/// `extension NamedContextDescriptorProtocol { ... }` and attribute to the
/// protocol, not to concrete descriptor types like `StructDescriptor`.
///
/// We exercise the protocol-extension methods through `Structs.StructTest`'s
/// `StructDescriptor`. The MangledName payload is a deep ABI tree we don't
/// embed as a literal; we assert its presence and the stable `name` string.
@Suite
final class NamedContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "NamedContextDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        NamedContextDescriptorProtocolBaseline.registeredTestMethodNames
    }

    @Test func name() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllReaders(
            file: { try fileDescriptor.name(in: machOFile) },
            image: { try imageDescriptor.name(in: machOImage) }
        )
        #expect(result == NamedContextDescriptorProtocolBaseline.structTest.name)

        // ReadingContext-based overload also exercised.
        let imageCtxName = try imageDescriptor.name(in: imageContext)
        #expect(imageCtxName == NamedContextDescriptorProtocolBaseline.structTest.name)
    }

    @Test func mangledName() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // MangledName isn't trivially Equatable for our needs; assert
        // presence at runtime against the baseline flag.
        let filePresence = (try? fileDescriptor.mangledName(in: machOFile)) != nil
        let imagePresence = (try? imageDescriptor.mangledName(in: machOImage)) != nil
        let imageCtxPresence = (try? imageDescriptor.mangledName(in: imageContext)) != nil

        #expect(filePresence == imagePresence)
        #expect(filePresence == imageCtxPresence)
        #expect(filePresence == NamedContextDescriptorProtocolBaseline.structTest.hasMangledName)
    }
}
