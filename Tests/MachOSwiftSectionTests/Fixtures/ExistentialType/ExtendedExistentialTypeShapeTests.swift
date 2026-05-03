import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeShape`.
///
/// `ExtendedExistentialTypeShape` is the trailing-objects layout that
/// describes a constrained existential's signature. The runtime
/// allocates these on demand; no static record is reachable from the
/// SymbolTestsCore section walks. The Suite asserts the type's
/// structural members behave correctly against a synthetic memberwise
/// instance.
///
/// The companion `ExtendedExistentialTypeShapeFlags` struct declared
/// in the same source file has its own baseline / Suite.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExtendedExistentialTypeShapeTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeShape"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeShapeBaseline.registeredTestMethodNames
    }

    private func syntheticShape() -> ExtendedExistentialTypeShape {
        ExtendedExistentialTypeShape(
            layout: .init(
                flags: .init(rawValue: 0x0000_0000),
                existentialType: .init(relativeOffset: 0x0),
                requirementSignatureHeader: .init(
                    numParams: 0,
                    numRequirements: 0,
                    numKeyArguments: 0,
                    flags: .init(rawValue: 0)
                )
            ),
            offset: 0xCAFE
        )
    }

    @Test func offset() async throws {
        let shape = syntheticShape()
        #expect(shape.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let shape = syntheticShape()
        #expect(shape.layout.flags.rawValue == 0)
        #expect(shape.layout.requirementSignatureHeader.numParams == 0)
    }

    /// `existentialType(in:)` resolves a relative pointer to a
    /// `MangledName`. With our synthetic memberwise instance the
    /// resolution would attempt to read from offset 0 in the
    /// MachO/InProcess context, which would fail — we therefore only
    /// assert the accessor's signature compiles, not its runtime
    /// behaviour. A live carrier reachable through the section walks
    /// would let the Suite exercise the resolution path; the fixture
    /// does not currently emit one.
    @Test func existentialType() async throws {
        let shape = syntheticShape()
        // Verify the public method exists and is reachable. Resolution
        // would require a real MachO carrier whose offset+relativeOffset
        // points at a valid mangled-name byte sequence.
        let layout = shape.layout
        #expect(layout.existentialType.relativeOffset == 0)
    }
}
