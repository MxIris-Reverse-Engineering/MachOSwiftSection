import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MethodDescriptorKind`.
///
/// `MethodDescriptorKind` is a `UInt8`-raw enum with six cases. The
/// Suite pins both the raw values and the `description` strings, so any
/// accidental renumbering or display tweak fails a test.
@Suite
final class MethodDescriptorKindTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDescriptorKind"
    static var registeredTestMethodNames: Set<String> {
        MethodDescriptorKindBaseline.registeredTestMethodNames
    }

    @Test func description() async throws {
        // Pin raw values + descriptions per case.
        #expect(MethodDescriptorKind.method.rawValue == MethodDescriptorKindBaseline.method.rawValue)
        #expect(MethodDescriptorKind.method.description == MethodDescriptorKindBaseline.method.description)

        #expect(MethodDescriptorKind.`init`.rawValue == MethodDescriptorKindBaseline.`init`.rawValue)
        #expect(MethodDescriptorKind.`init`.description == MethodDescriptorKindBaseline.`init`.description)

        #expect(MethodDescriptorKind.getter.rawValue == MethodDescriptorKindBaseline.getter.rawValue)
        #expect(MethodDescriptorKind.getter.description == MethodDescriptorKindBaseline.getter.description)

        #expect(MethodDescriptorKind.setter.rawValue == MethodDescriptorKindBaseline.setter.rawValue)
        #expect(MethodDescriptorKind.setter.description == MethodDescriptorKindBaseline.setter.description)

        #expect(MethodDescriptorKind.modifyCoroutine.rawValue == MethodDescriptorKindBaseline.modifyCoroutine.rawValue)
        #expect(MethodDescriptorKind.modifyCoroutine.description == MethodDescriptorKindBaseline.modifyCoroutine.description)

        #expect(MethodDescriptorKind.readCoroutine.rawValue == MethodDescriptorKindBaseline.readCoroutine.rawValue)
        #expect(MethodDescriptorKind.readCoroutine.description == MethodDescriptorKindBaseline.readCoroutine.description)
    }
}
