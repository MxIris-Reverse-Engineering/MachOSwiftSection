import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ExistentialTypeMetadata`.
///
/// `ExistentialTypeMetadata` is the runtime metadata for `any P` /
/// `any P & Q`. The Swift runtime allocates these on demand and there's
/// no static record in `__swift5_types` for the existential itself.
/// The Suite asserts structural members behave against synthetic
/// memberwise instances exercising the documented representation arms
/// (opaque / class-bounded / error).
///
/// `superclassConstraint(in:)` and `protocols(in:)` are exercised
/// against a flag layout that yields empty results — calling them on
/// our synthetic instance with a real reader would fault on bogus
/// offsets, but the early-out paths (no superclass, zero protocols)
/// short-circuit safely.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExistentialTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExistentialTypeMetadataBaseline.registeredTestMethodNames
    }

    /// `flags` raw value chosen so:
    /// - bit 31 clear → `classConstraint == .class` (avoids the UInt8
    ///   conversion bug discussed in ExistentialTypeFlagsBaseline)
    /// - low 24 bits zero → `numberOfWitnessTables == 0`
    /// - bit 30 clear → no superclass
    /// - bits 24-29 zero → `specialProtocol == .none`
    private func syntheticOpaqueExistential() -> ExistentialTypeMetadata {
        ExistentialTypeMetadata(
            layout: .init(
                kind: 0x303,
                flags: .init(rawValue: 0x0000_0001),  // class-bound, 1 witness table
                numberOfProtocols: 0
            ),
            offset: 0xCAFE
        )
    }

    /// Pure-ObjC existential — class-bounded with zero witness tables.
    private func syntheticObjCExistential() -> ExistentialTypeMetadata {
        ExistentialTypeMetadata(
            layout: .init(
                kind: 0x303,
                flags: .init(rawValue: 0x0000_0000),
                numberOfProtocols: 0
            ),
            offset: 0xBEEF
        )
    }

    /// Error special-protocol existential.
    private func syntheticErrorExistential() -> ExistentialTypeMetadata {
        ExistentialTypeMetadata(
            layout: .init(
                kind: 0x303,
                flags: .init(rawValue: 0x0100_0001),
                numberOfProtocols: 0
            ),
            offset: 0xFEED
        )
    }

    @Test func offset() async throws {
        let metadata = syntheticOpaqueExistential()
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = syntheticOpaqueExistential()
        #expect(metadata.layout.kind == 0x303)
        #expect(metadata.layout.numberOfProtocols == 0)
    }

    @Test func isClassBounded() async throws {
        // Both syntheticOpaqueExistential and syntheticObjCExistential are
        // class-bounded (bit 31 clear). The naming "opaque" here refers to
        // protocol layout, NOT class constraint — we can't construct a
        // value-bounded carrier without tripping the UInt8 conversion bug
        // documented in ExistentialTypeFlagsBaseline.
        #expect(syntheticOpaqueExistential().isClassBounded == true)
        #expect(syntheticObjCExistential().isClassBounded == true)
    }

    @Test func isObjC() async throws {
        // ObjC-only when class-bounded AND zero witness tables.
        #expect(syntheticOpaqueExistential().isObjC == false)  // 1 witness table
        #expect(syntheticObjCExistential().isObjC == true)     // 0 witness tables
    }

    @Test func representation() async throws {
        // class-bounded, no special-protocol → .class
        #expect(syntheticOpaqueExistential().representation == .class)
        // class-bounded, no special-protocol → .class
        #expect(syntheticObjCExistential().representation == .class)
        // special-protocol == .error → .error
        #expect(syntheticErrorExistential().representation == .error)
    }

    @Test func superclassConstraint() async throws {
        // No superclass-constraint bit set → returns nil regardless of
        // reader. The `protocols(in:)` accessor short-circuits before
        // reading any actual bytes.
        let metadata = syntheticOpaqueExistential()
        let viaFile = try metadata.superclassConstraint(in: machOFile)
        let viaImage = try metadata.superclassConstraint(in: machOImage)
        let viaContext = try metadata.superclassConstraint(in: imageContext)
        #expect(viaFile == nil)
        #expect(viaImage == nil)
        #expect(viaContext == nil)
    }

    @Test func protocols() async throws {
        // numberOfProtocols == 0 → returns [] regardless of reader.
        let metadata = syntheticOpaqueExistential()
        let viaFile = try metadata.protocols(in: machOFile)
        let viaImage = try metadata.protocols(in: machOImage)
        let viaContext = try metadata.protocols(in: imageContext)
        #expect(viaFile.isEmpty)
        #expect(viaImage.isEmpty)
        #expect(viaContext.isEmpty)
    }
}
