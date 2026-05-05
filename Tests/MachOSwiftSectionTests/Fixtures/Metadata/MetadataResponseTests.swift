import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataResponse`.
///
/// `MetadataResponse` is the (`Pointer<MetadataWrapper>`, `MetadataState`)
/// tuple returned by `MetadataAccessorFunction.callAsFunction(...)`. Live
/// instances are reachable only through MachOImage's accessor invocation;
/// the Suite materialises one for `Structs.StructTest` and asserts the
/// response's `value` resolves to a non-nil `StructMetadata` and the
/// `state` is `.complete` for blocking calls.
///
/// **Reader asymmetry:** the response originates from MachOImage's accessor
/// invocation; `MachOFile` cannot invoke runtime functions.
@Suite
final class MetadataResponseTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataResponse"
    static var registeredTestMethodNames: Set<String> {
        MetadataResponseBaseline.registeredTestMethodNames
    }

    private func loadStructTestResponse() throws -> MetadataResponse {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))
        return try accessor(request: .completeAndBlocking)
    }

    /// `value` is a `Pointer<MetadataWrapper>` that resolves to the
    /// requested struct's wrapper.
    @Test func value() async throws {
        let response = try loadStructTestResponse()
        let wrapper = try response.value.resolve(in: machOImage)
        #expect(wrapper.isStruct)
    }

    /// `state` decodes the metadata state from the response. For a
    /// blocking complete request, the runtime returns `.complete`.
    @Test func state() async throws {
        let response = try loadStructTestResponse()
        #expect(response.state == .complete)
    }
}
