import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FunctionTypeFlags<UInt64>`.
///
/// Phase C2: real InProcess test against `((Int) -> Void).self`. We
/// resolve the runtime-allocated `FunctionTypeMetadata` and assert its
/// `flags.numberOfParameters` against the ABI literal pinned in the
/// regenerated baseline. The other accessors (`rawValue`, `convention`,
/// `isThrowing`, etc.) are pure raw-value bit decoders and are tracked
/// via the sentinel allowlist (`pureDataUtilityEntries`).
@Suite
final class FunctionTypeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeFlags"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeFlagsBaseline.registeredTestMethodNames
    }

    @Test func numberOfParameters() async throws {
        let result = try usingInProcessOnly { context in
            try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context)
                .layout.flags.numberOfParameters
        }
        #expect(result == FunctionTypeFlagsBaseline.stdlibFunctionIntToVoid.numberOfParameters)
    }
}
