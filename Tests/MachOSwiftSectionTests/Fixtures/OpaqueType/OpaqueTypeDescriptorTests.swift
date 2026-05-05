import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `OpaqueTypeDescriptor`.
///
/// SymbolTestsCore's opaque-type descriptors aren't directly reachable
/// on the current toolchain (see OpaqueTypeBaseline). The Suite asserts
/// structural members behave against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class OpaqueTypeDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "OpaqueTypeDescriptor"
    static var registeredTestMethodNames: Set<String> {
        OpaqueTypeDescriptorBaseline.registeredTestMethodNames
    }

    private func syntheticDescriptor() -> OpaqueTypeDescriptor {
        OpaqueTypeDescriptor(
            layout: .init(
                flags: .init(rawValue: UInt32(ContextDescriptorKind.opaqueType.rawValue)),
                parent: .init(relativeOffsetPlusIndirect: -16)
            ),
            offset: 0xCAFE
        )
    }

    @Test func offset() async throws {
        let descriptor = syntheticDescriptor()
        #expect(descriptor.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let descriptor = syntheticDescriptor()
        #expect(descriptor.layout.flags.kind == .opaqueType)
        #expect(descriptor.layout.parent.relativeOffsetPlusIndirect == -16)
    }
}
