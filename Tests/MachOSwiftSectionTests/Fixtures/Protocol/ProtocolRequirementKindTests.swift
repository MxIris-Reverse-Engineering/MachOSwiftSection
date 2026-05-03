import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolRequirementKind`.
///
/// The only public member declared in source is the
/// `CustomStringConvertible.description` computed property; the cases
/// themselves are out of scope for `PublicMemberScanner`. We assert the
/// description string for every case to exercise the switch coverage.
@Suite
final class ProtocolRequirementKindTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolRequirementKind"
    static var registeredTestMethodNames: Set<String> {
        ProtocolRequirementKindBaseline.registeredTestMethodNames
    }

    @Test func description() async throws {
        #expect(ProtocolRequirementKind.baseProtocol.description == ProtocolRequirementKindBaseline.baseProtocolDescription)
        #expect(ProtocolRequirementKind.method.description == ProtocolRequirementKindBaseline.methodDescription)
        #expect(ProtocolRequirementKind.`init`.description == ProtocolRequirementKindBaseline.initDescription)
        #expect(ProtocolRequirementKind.getter.description == ProtocolRequirementKindBaseline.getterDescription)
        #expect(ProtocolRequirementKind.setter.description == ProtocolRequirementKindBaseline.setterDescription)
        #expect(ProtocolRequirementKind.readCoroutine.description == ProtocolRequirementKindBaseline.readCoroutineDescription)
        #expect(ProtocolRequirementKind.modifyCoroutine.description == ProtocolRequirementKindBaseline.modifyCoroutineDescription)
        #expect(ProtocolRequirementKind.associatedTypeAccessFunction.description == ProtocolRequirementKindBaseline.associatedTypeAccessFunctionDescription)
        #expect(ProtocolRequirementKind.associatedConformanceAccessFunction.description == ProtocolRequirementKindBaseline.associatedConformanceAccessFunctionDescription)
    }
}
