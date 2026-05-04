import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeMetadata`.
///
/// Phase C3: real InProcess test against `(any Sequence<Int>).self` — a
/// parameterized-protocol existential whose runtime metadata kind is
/// `extendedExistential` (0x307). We resolve via
/// `InProcessMetadataPicker.stdlibAnyEquatable` (the constant retains its
/// historical name; the underlying type is the parameterized
/// `Sequence<Int>` because `Equatable` is not parameterized) and assert
/// the wrapper's observable `layout` (kind + shape pointer) and `offset`
/// (runtime metadata pointer bit-pattern) against ABI literals pinned in
/// the regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
///
/// Note: parameterized protocol existential metadata requires macOS 13.0+
/// at the language-runtime level. Tests guard the in-process metadata
/// access with `if #available` rather than annotating the suite class.
@Suite
final class ExtendedExistentialTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        // Returning a struct directly as a tuple is not Equatable, so
        // capture both fields separately.
        let kindRaw = try usingInProcessOnly { context in
            try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context).kind.rawValue
        }
        let shapeIsNonZero = try usingInProcessOnly { context in
            try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
                .layout.shape.address != 0
        }
        // The runtime extended-existential metadata's layout: kind decodes
        // to `MetadataKind.extendedExistential` (0x307); `shape` is a
        // pointer to the runtime-allocated `ExtendedExistentialTypeShape`.
        // The shape's exact address is non-deterministic across process
        // invocations (runtime allocates lazily on first access), so we
        // assert the pointer is non-null rather than pinning the literal.
        #expect(kindRaw == ExtendedExistentialTypeMetadataBaseline.stdlibAnyEquatable.kindRawValue)
        #expect(shapeIsNonZero == true)
    }

    @Test func offset() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        let resolvedOffset = try usingInProcessOnly { context in
            try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibAnyEquatable)
        #expect(resolvedOffset == expectedOffset)
    }
}
