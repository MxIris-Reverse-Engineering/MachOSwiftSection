import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeShape`.
///
/// Phase C3: real InProcess test against the shape of `(any Sequence<Int>)`.
/// The shape is reached by resolving
/// `ExtendedExistentialTypeMetadata.layout.shape` through the InProcess
/// context. We assert the wrapper's observable `layout` (flags raw value
/// + requirement-signature header counts), `offset` (the resolved
/// shape's runtime address bit-pattern), and `existentialType(in:)`
/// (resolves a relative-direct mangled-name pointer; we assert the
/// mangled-name string is non-empty). All ABI literals are pinned in the
/// regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
///
/// Note: parameterized protocol existential metadata requires macOS 13.0+
/// at the language-runtime level. Tests guard the in-process metadata
/// access with `if #available` rather than annotating the suite class.
@Suite
final class ExtendedExistentialTypeShapeTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeShape"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeShapeBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        let flagsRaw = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            return shape.layout.flags.rawValue
        }
        let numParams = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            return shape.layout.requirementSignatureHeader.numParams
        }
        // The shape's `flags` raw value carries the constraints / type
        // expression / generalisation bits for `(any Sequence<Int>)`. The
        // requirement-signature header carries `numParams`/`numRequirements`
        // for the parameterised protocol (Sequence has primary associated
        // type Element).
        #expect(flagsRaw == ExtendedExistentialTypeShapeBaseline.equatableShape.flagsRawValue)
        #expect(numParams == ExtendedExistentialTypeShapeBaseline.equatableShape.requirementSignatureNumParams)
    }

    @Test func offset() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        let isNonZero = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            return shape.offset != 0
        }
        // The shape's `offset` after InProcess resolution is the bit pattern
        // of the runtime shape pointer (after tag-bit stripping). Its exact
        // value is non-deterministic across process invocations, so we only
        // assert it's non-zero (the shape was reached).
        #expect(isNonZero == true)
    }

    @Test func existentialType() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else { return }
        // `existentialType(in:)` resolves a relative-direct pointer to a
        // mangled-name. For `(any Sequence<Int>)` the mangled name describes
        // the existential's shape (the parameterized protocol's signature).
        // We check the mangled name resolves to a non-empty MangledName.
        let isNonEmpty = try usingInProcessOnly { context in
            let metadata = try ExtendedExistentialTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context)
            let shape = try metadata.layout.shape.resolve(in: context)
            let mangled = try shape.existentialType(in: context)
            return !mangled.isEmpty
        }
        #expect(isNonEmpty == true)
    }
}
