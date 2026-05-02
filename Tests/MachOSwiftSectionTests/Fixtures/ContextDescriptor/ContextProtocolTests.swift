import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ContextProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// the `parent()` family of overloads declared in
/// `extension ContextProtocol { ... }` belongs to this Suite, not to the
/// concrete `Struct`/`Enum`/`Class` Suites that conform.
///
/// We exercise the protocol-extension method through a `Struct` context
/// built off `Structs.StructTest`'s descriptor.
@Suite
final class ContextProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextProtocol"
    static var registeredTestMethodNames: Set<String> {
        ContextProtocolBaseline.registeredTestMethodNames
    }

    @Test func parent() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let fileContextWrapper = try Struct(descriptor: fileDescriptor, in: machOFile)
        let imageContextWrapper = try Struct(descriptor: imageDescriptor, in: machOImage)

        let presence = try acrossAllReaders(
            file: { (try fileContextWrapper.parent(in: machOFile)) != nil },
            image: { (try imageContextWrapper.parent(in: machOImage)) != nil }
        )
        #expect(presence == ContextProtocolBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageContextWrapper.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextProtocolBaseline.structTest.hasParent)
    }
}
