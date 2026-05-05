import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExistentialTypeMetadata`.
///
/// Phase C3: real InProcess tests against stdlib existentials. Two
/// metadata sources are used:
///
///   - `Any.self` (`stdlibAnyExistential`) — maximally-general existential
///     used to anchor `layout`, `offset`, `numberOfProtocols`, plus the
///     `superclassConstraint` / `protocols` short-circuit paths (both
///     return null/empty when `numberOfProtocols == 0`).
///
///   - `AnyObject.self` (`stdlibAnyObjectExistential`) — class-bounded
///     existential with zero witness tables (flags `0x0`). Required for
///     `isClassBounded` / `isObjC` / `representation` because calling
///     `classConstraint` on `Any.self`'s flags traps (`UInt8(rawValue &
///     0x80000000)` overflows). `AnyObject` decodes cleanly to
///     `classConstraint == .class`, no special protocol, zero witnesses.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExistentialTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExistentialTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let resolved = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
        }
        // The runtime existential metadata's layout: kind decodes to
        // MetadataKind.existential (0x303); flags raw value encodes
        // `classConstraint == .any`; numberOfProtocols is 0.
        #expect(resolved.kind.rawValue == ExistentialTypeMetadataBaseline.stdlibAnyExistential.kindRawValue)
        #expect(resolved.layout.flags.rawValue == ExistentialTypeMetadataBaseline.stdlibAnyExistential.flagsRawValue)
        #expect(resolved.layout.numberOfProtocols == ExistentialTypeMetadataBaseline.stdlibAnyExistential.numberOfProtocols)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibAnyExistential)
        #expect(resolvedOffset == expectedOffset)
    }

    @Test func isClassBounded() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyObjectExistential, in: context).isClassBounded
        }
        // `AnyObject.self` flags raw is `0x0` — bit 31 clear means
        // `classConstraint == .class`, so `isClassBounded == true`.
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyObjectExistential.isClassBounded)
    }

    @Test func isObjC() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyObjectExistential, in: context).isObjC
        }
        // `AnyObject` is class-bounded with zero witness tables → ObjC.
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyObjectExistential.isObjC)
    }

    @Test func representation() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyObjectExistential, in: context).representation
        }
        // class-bounded, no special-protocol → `.class`.
        #expect(result == .class)
    }

    @Test func superclassConstraint() async throws {
        // `Any.self` has no superclass-constraint bit set; returns nil.
        let result = try usingInProcessOnly { context in
            (try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .superclassConstraint(in: context)) == nil
        }
        #expect(result == true)
    }

    @Test func protocols() async throws {
        // `Any.self` has zero protocols; returns empty array.
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyExistential, in: context)
                .protocols(in: context)
                .count
        }
        #expect(result == 0)
    }
}
