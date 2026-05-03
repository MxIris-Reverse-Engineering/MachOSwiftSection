import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeLayout`.
///
/// `TypeLayout` is the (size, stride, flags, extraInhabitantCount)
/// quadruple projected from a `ValueWitnessTable`. Pure value-type —
/// the Suite re-evaluates each accessor against a synthetic instance.
@Suite
final class TypeLayoutTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeLayout"
    static var registeredTestMethodNames: Set<String> {
        TypeLayoutBaseline.registeredTestMethodNames
    }

    /// Construct a synthetic `TypeLayout` representing a non-POD,
    /// inline, bitwise-takable, copyable type with alignment 8 (mask 7),
    /// size 16, stride 16, no extra inhabitants.
    private func syntheticLayout() -> TypeLayout {
        TypeLayout(
            size: 16,
            stride: 16,
            flags: ValueWitnessFlags(rawValue: 0x0001_0007),
            extraInhabitantCount: 0
        )
    }

    @Test func size() async throws {
        let layout = syntheticLayout()
        #expect(layout.size == 16)
    }

    @Test func stride() async throws {
        let layout = syntheticLayout()
        #expect(layout.stride == 16)
    }

    @Test func flags() async throws {
        let layout = syntheticLayout()
        #expect(layout.flags.rawValue == 0x0001_0007)
    }

    @Test func extraInhabitantCount() async throws {
        let layout = syntheticLayout()
        #expect(layout.extraInhabitantCount == 0)
    }

    @Test("subscript(dynamicMember:)") func dynamicSubscript() async throws {
        let layout = syntheticLayout()
        // The dynamicMember subscript bridges to ValueWitnessFlags
        // keypaths. Read `isPOD` and `alignment` via the bridged keypath.
        let isPOD: Bool = layout.isPOD
        let alignment: StoredSize = layout.alignment
        #expect(isPOD == false)
        #expect(alignment == 8)
    }

    @Test func description() async throws {
        let layout = syntheticLayout()
        let description = layout.description
        // The format is "TypeLayout(size: <n>, stride: <n>, alignment:
        // <n>, extraInhabitantCount: <n>)" — assert the prefix and key
        // numeric fields rather than the full string (Swift Int print
        // formats are stable but subject to localization in some
        // contexts).
        #expect(description.hasPrefix("TypeLayout("))
        #expect(description.contains("size: 16"))
        #expect(description.contains("stride: 16"))
        #expect(description.contains("alignment: 8"))
        #expect(description.contains("extraInhabitantCount: 0"))
    }

    @Test func debugDescription() async throws {
        let layout = syntheticLayout()
        let debugDescription = layout.debugDescription
        // The debugDescription extends the description with the
        // additional flag bits (isPOD, isInlineStorage, etc.).
        #expect(debugDescription.hasPrefix("TypeLayout("))
        #expect(debugDescription.contains("isPOD: false"))
        #expect(debugDescription.contains("isInlineStorage: true"))
        #expect(debugDescription.contains("isCopyable: true"))
        #expect(debugDescription.contains("isBitwiseTakable: true"))
    }
}
