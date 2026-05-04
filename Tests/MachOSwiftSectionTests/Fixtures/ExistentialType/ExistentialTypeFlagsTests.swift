import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExistentialTypeFlags`.
///
/// Phase C3: real InProcess test against the flags slice of stdlib
/// existentials. Two metadata sources are used:
///
///   - `Any.self` flags (`0x80000000`) — anchor `rawValue`,
///     `init(rawValue:)`, `numberOfWitnessTables` (0),
///     `hasSuperclassConstraint` (false), `specialProtocol` (`.none`).
///
///   - `AnyObject.self` flags (`0x0`) — anchor `classConstraint` because
///     `Any.self`'s flags trap `UInt8(rawValue & 0x80000000)`.
@Suite
final class ExistentialTypeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialTypeFlags"
    static var registeredTestMethodNames: Set<String> {
        ExistentialTypeFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        let result = try usingInProcessOnly { context in
            let metadata = try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
            return ExistentialTypeFlags(rawValue: metadata.layout.flags.rawValue).rawValue
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyExistential.rawValue)
    }

    @Test func rawValue() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .layout.flags.rawValue
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyExistential.rawValue)
    }

    @Test func numberOfWitnessTables() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .layout.flags.numberOfWitnessTables
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyExistential.numberOfWitnessTables)
    }

    @Test func classConstraint() async throws {
        // `AnyObject.self` flags decode to `classConstraint == .class`.
        // `Any.self` flags would trap (UInt8 conversion overflow).
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyObjectExistential, in: context)
                .layout.flags.classConstraint.rawValue
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyObjectExistential.classConstraintRawValue)
    }

    @Test func hasSuperclassConstraint() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .layout.flags.hasSuperclassConstraint
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyExistential.hasSuperclassConstraint)
    }

    @Test func specialProtocol() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .layout.flags.specialProtocol.rawValue
        }
        #expect(result == ExistentialTypeFlagsBaseline.stdlibAnyExistential.specialProtocolRawValue)
    }
}
