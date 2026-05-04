import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FunctionTypeMetadata`.
///
/// Phase C2: real InProcess test against `((Int) -> Void).self`. We
/// resolve the runtime-allocated `FunctionTypeMetadata` from
/// `InProcessMetadataPicker.stdlibFunctionIntToVoid` and assert its
/// observable `layout` (kind + flags raw value) and `offset` (runtime
/// metadata pointer bit-pattern) against ABI literals pinned in the
/// regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class FunctionTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let resolved = try usingInProcessOnly { context in
            try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context)
        }
        // The runtime function metadata's layout: kind decodes to
        // MetadataKind.function (0x302); flags raw value encodes 1
        // parameter + escaping bit set.
        #expect(resolved.kind.rawValue == FunctionTypeMetadataBaseline.stdlibFunctionIntToVoid.kindRawValue)
        #expect(resolved.layout.flags.rawValue == FunctionTypeMetadataBaseline.stdlibFunctionIntToVoid.flagsRawValue)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibFunctionIntToVoid)
        #expect(resolvedOffset == expectedOffset)
    }
}
