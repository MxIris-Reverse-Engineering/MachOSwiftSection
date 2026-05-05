import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeShapeFlags`.
///
/// Phase C3: real InProcess test against the shape flags of
/// `(any Sequence<Int>).self`'s shape. We resolve the shape via
/// `InProcessMetadataPicker.stdlibAnyEquatable`, read its `flags` raw
/// value, and round-trip through `init(rawValue:)` / `rawValue`. The ABI
/// literal is pinned in the regenerated baseline.
///
/// Note: parameterized protocol existential metadata requires macOS 13.0+
/// at the language-runtime level. Tests guard the in-process metadata
/// access with `if #available` rather than annotating the suite class.
@Suite
final class ExtendedExistentialTypeShapeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeShapeFlags"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeShapeFlagsBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializer() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        let result = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            return ExtendedExistentialTypeShapeFlags(rawValue: shape.layout.flags.rawValue).rawValue
        }
        #expect(result == ExtendedExistentialTypeShapeFlagsBaseline.equatableShape.rawValue)
    }

    @Test func rawValue() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        let result = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            return shape.layout.flags.rawValue
        }
        #expect(result == ExtendedExistentialTypeShapeFlagsBaseline.equatableShape.rawValue)
    }
}
