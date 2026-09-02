import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Command-line surface for evolution proposal
/// `exported-only-interface`: `swift-section interface --exported-only`
/// exists and defaults to off — the contract that keeps default output
/// byte-identical. `dump` deliberately has no such flag (out of scope).
@Suite
struct ExportedOnlyFlagTests {
    @Test func interfaceFlagDefaultsOff() throws {
        let command = try InterfaceCommand.parse(["/tmp/example"])
        #expect(command.exportedOnly == false)
    }

    @Test func interfaceFlagParses() throws {
        let command = try InterfaceCommand.parse(["/tmp/example", "--exported-only"])
        #expect(command.exportedOnly == true)
    }

    @Test func dumpHasNoSuchFlag() throws {
        #expect(throws: (any Error).self) {
            try DumpCommand.parse(["/tmp/example", "--exported-only"])
        }
    }
}
