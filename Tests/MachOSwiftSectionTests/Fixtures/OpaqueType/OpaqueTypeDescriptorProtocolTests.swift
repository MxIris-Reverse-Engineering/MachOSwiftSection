import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `OpaqueTypeDescriptorProtocol`'s extension
/// members.
///
/// The protocol contributes one extension accessor —
/// `numUnderlyingTypeArugments` (note: misspelled as "Arugments" in
/// source). SymbolTestsCore's opaque-type descriptors aren't directly
/// reachable on the current toolchain (see OpaqueTypeBaseline), so the
/// Suite exercises the accessor against synthetic memberwise
/// `OpaqueTypeDescriptor` instances whose `ContextDescriptorFlags`
/// kind-specific bits encode known counts.
@Suite
final class OpaqueTypeDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "OpaqueTypeDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        OpaqueTypeDescriptorProtocolBaseline.registeredTestMethodNames
    }

    private func descriptor(withUnderlyingTypeArugments count: UInt16) -> OpaqueTypeDescriptor {
        // ContextDescriptorFlags kind in low 5 bits + kindSpecificFlagsRawValue
        // in upper 16 bits. We pack `count` into the upper 16 bits to
        // exercise the accessor path.
        let kind = UInt32(ContextDescriptorKind.opaqueType.rawValue)
        let kindSpecific = UInt32(count) << 16
        return OpaqueTypeDescriptor(
            layout: .init(
                flags: .init(rawValue: kind | kindSpecific),
                parent: .init(relativeOffsetPlusIndirect: 0)
            ),
            offset: 0
        )
    }

    @Test func numUnderlyingTypeArugments() async throws {
        for count in [UInt16(0), 1, 3, 8] {
            let descriptor = descriptor(withUnderlyingTypeArugments: count)
            #expect(descriptor.numUnderlyingTypeArugments == Int(count))
        }
    }
}
