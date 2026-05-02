import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ExtraClassDescriptorFlags`.
///
/// The flags are a `UInt32` `FlagSet` with one named bit
/// (`hasObjCResilientClassStub`). The fixture's classes don't have a
/// resilient ObjC stub, so we exercise the flag derivation by
/// constructing instances with known raw values.
@Suite
final class ExtraClassDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtraClassDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        ExtraClassDescriptorFlagsBaseline.registeredTestMethodNames
    }

    @Test func rawValue() async throws {
        let zero = ExtraClassDescriptorFlags(rawValue: ExtraClassDescriptorFlagsBaseline.zeroRawValue)
        #expect(zero.rawValue == ExtraClassDescriptorFlagsBaseline.zeroRawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        // Round-trip: bit 0 unset → flag is false.
        let zero = ExtraClassDescriptorFlags(rawValue: ExtraClassDescriptorFlagsBaseline.zeroRawValue)
        #expect(zero.rawValue == ExtraClassDescriptorFlagsBaseline.zeroRawValue)
        #expect(zero.hasObjCResilientClassStub == false)

        // Round-trip: bit 0 set → flag is true.
        let stub = ExtraClassDescriptorFlags(rawValue: ExtraClassDescriptorFlagsBaseline.stubBitRawValue)
        #expect(stub.rawValue == ExtraClassDescriptorFlagsBaseline.stubBitRawValue)
        #expect(stub.hasObjCResilientClassStub == true)
    }

    @Test func hasObjCResilientClassStub() async throws {
        let zero = ExtraClassDescriptorFlags(rawValue: ExtraClassDescriptorFlagsBaseline.zeroRawValue)
        let stub = ExtraClassDescriptorFlags(rawValue: ExtraClassDescriptorFlagsBaseline.stubBitRawValue)
        #expect(zero.hasObjCResilientClassStub == false)
        #expect(stub.hasObjCResilientClassStub == true)
    }
}
