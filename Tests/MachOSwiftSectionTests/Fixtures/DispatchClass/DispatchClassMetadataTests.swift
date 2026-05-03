import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `DispatchClassMetadata`.
///
/// `DispatchClassMetadata` mirrors libdispatch's runtime class layout
/// (`OS_object`). It's not a Swift type descriptor and no static
/// carrier is reachable from SymbolTestsCore. The Suite asserts
/// structural members behave against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class DispatchClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "DispatchClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        DispatchClassMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = DispatchClassMetadata(
            layout: .init(
                kind: 0,
                opaque: .init(address: 0x1000),
                opaqueObjC1: .init(address: 0x1010),
                opaqueObjC2: .init(address: 0x1020),
                opaqueObjC3: .init(address: 0x1030),
                vTableType: 0xCAFE_BABE,
                vTableInvoke: .init(address: 0x2000)
            ),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = DispatchClassMetadata(
            layout: .init(
                kind: 0,
                opaque: .init(address: 0x3000),
                opaqueObjC1: .init(address: 0x3010),
                opaqueObjC2: .init(address: 0x3020),
                opaqueObjC3: .init(address: 0x3030),
                vTableType: 0xDEAD_BEEF,
                vTableInvoke: .init(address: 0x4000)
            ),
            offset: 0
        )
        #expect(metadata.layout.kind == 0)
        #expect(metadata.layout.vTableType == 0xDEAD_BEEF)
        #expect(metadata.layout.vTableInvoke.address == 0x4000)
    }
}
