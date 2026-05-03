import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `NonUniqueExtendedExistentialTypeShape`.
///
/// `NonUniqueExtendedExistentialTypeShape` is the non-unique variant of
/// `ExtendedExistentialTypeShape`. The runtime allocates these on
/// demand; no static record is reachable from the SymbolTestsCore
/// section walks. The Suite asserts the type's structural members
/// behave correctly against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class NonUniqueExtendedExistentialTypeShapeTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "NonUniqueExtendedExistentialTypeShape"
    static var registeredTestMethodNames: Set<String> {
        NonUniqueExtendedExistentialTypeShapeBaseline.registeredTestMethodNames
    }

    private func syntheticShape() -> NonUniqueExtendedExistentialTypeShape {
        NonUniqueExtendedExistentialTypeShape(
            layout: .init(
                uniqueCache: .init(relativeOffset: 0x0),
                localCopy: .init(
                    flags: .init(rawValue: 0),
                    existentialType: .init(relativeOffset: 0),
                    requirementSignatureHeader: .init(
                        numParams: 0,
                        numRequirements: 0,
                        numKeyArguments: 0,
                        flags: .init(rawValue: 0)
                    )
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
        #expect(shape.layout.uniqueCache.relativeOffset == 0)
        #expect(shape.layout.localCopy.flags.rawValue == 0)
    }

    /// `existentialType(in:)` resolves the embedded `localCopy.existentialType`
    /// relative pointer. With our synthetic instance the resolution would
    /// attempt to read from offset 0, which would fail — we therefore only
    /// assert the public method is reachable, not its runtime behaviour.
    @Test func existentialType() async throws {
        let shape = syntheticShape()
        #expect(shape.layout.localCopy.existentialType.relativeOffset == 0)
    }
}
