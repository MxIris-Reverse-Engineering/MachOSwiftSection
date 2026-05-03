import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ClassFlags`.
///
/// `ClassFlags` is a `UInt32`-raw enum with five named cases. There are no
/// derived properties, so the Suite simply round-trips each case's raw
/// value to catch accidental renumbering. The baseline records no
/// member names because none of the cases or static utilities are
/// scanner-visible as method-keyed members.
@Suite
final class ClassFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassFlags"
    static var registeredTestMethodNames: Set<String> {
        ClassFlagsBaseline.registeredTestMethodNames
    }

    @Test func rawValuesMatchBaseline() async throws {
        #expect(ClassFlags.isSwiftPreStableABI.rawValue == ClassFlagsBaseline.isSwiftPreStableABI)
        #expect(ClassFlags.usesSwiftRefcounting.rawValue == ClassFlagsBaseline.usesSwiftRefcounting)
        #expect(ClassFlags.hasCustomObjCName.rawValue == ClassFlagsBaseline.hasCustomObjCName)
        #expect(ClassFlags.isStaticSpecialization.rawValue == ClassFlagsBaseline.isStaticSpecialization)
        #expect(ClassFlags.isCanonicalStaticSpecialization.rawValue == ClassFlagsBaseline.isCanonicalStaticSpecialization)
    }

    @Test func roundTripFromRawValue() async throws {
        #expect(ClassFlags(rawValue: ClassFlagsBaseline.isSwiftPreStableABI) == .isSwiftPreStableABI)
        #expect(ClassFlags(rawValue: ClassFlagsBaseline.usesSwiftRefcounting) == .usesSwiftRefcounting)
        #expect(ClassFlags(rawValue: ClassFlagsBaseline.hasCustomObjCName) == .hasCustomObjCName)
        #expect(ClassFlags(rawValue: ClassFlagsBaseline.isStaticSpecialization) == .isStaticSpecialization)
        #expect(ClassFlags(rawValue: ClassFlagsBaseline.isCanonicalStaticSpecialization) == .isCanonicalStaticSpecialization)
    }
}
