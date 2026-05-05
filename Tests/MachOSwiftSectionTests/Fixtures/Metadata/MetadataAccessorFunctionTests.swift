import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataAccessorFunction`.
///
/// `MetadataAccessorFunction` wraps a runtime function pointer to a Swift
/// metadata accessor. The pointer can only be obtained from a loaded
/// MachOImage (the function lives in the image's text segment). The Suite
/// invokes the accessor for `Structs.StructTest` and asserts the
/// resulting `MetadataResponse` resolves to a non-nil `StructMetadata`.
///
/// **Reader asymmetry:** the accessor pointer is reachable solely through
/// `MachOImage`. `MachOFile` cannot resolve runtime function pointers so
/// no MachOFile assertion is made here.
///
/// `init(ptr:)` is `package`-scoped and not visited by `PublicMemberScanner`;
/// the six `callAsFunction` overloads collapse to a single `MethodKey`.
@Suite
final class MetadataAccessorFunctionTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataAccessorFunction"
    static var registeredTestMethodNames: Set<String> {
        MetadataAccessorFunctionBaseline.registeredTestMethodNames
    }

    /// `callAsFunction(request:)` invokes the accessor with no metadata or
    /// witness-table arguments and returns a complete metadata response.
    @Test func callAsFunction() async throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let accessor = try required(try descriptor.metadataAccessorFunction(in: machOImage))

        // Zero-argument variant.
        let response = try accessor(request: .init())
        let wrapper = try response.value.resolve(in: machOImage)
        #expect(wrapper.isStruct)

        // Same accessor, asserting the in-process variant returns the same
        // wrapper kind (the response's value pointer is stable across
        // invocations).
        let response2 = try accessor(request: .init())
        let wrapper2 = try response2.value.resolve(in: machOImage)
        #expect(wrapper2.isStruct)
    }
}
