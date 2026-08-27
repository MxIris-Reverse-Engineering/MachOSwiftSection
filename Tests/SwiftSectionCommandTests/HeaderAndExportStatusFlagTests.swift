import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Command-line surface for evolution proposal 0008: the `--emit-header`
/// and `--emit-export-status` flags exist on both `interface` and `dump`,
/// and both default to off — the contract that keeps default output
/// byte-identical.
@Suite
struct HeaderAndExportStatusFlagTests {
    @Test func interfaceFlagsDefaultOff() throws {
        let command = try InterfaceCommand.parse(["/tmp/example"])
        #expect(command.emitHeader == false)
        #expect(command.emitExportStatus == false)
    }

    @Test func interfaceFlagsParse() throws {
        let command = try InterfaceCommand.parse(["/tmp/example", "--emit-header", "--emit-export-status"])
        #expect(command.emitHeader == true)
        #expect(command.emitExportStatus == true)
    }

    @Test func dumpFlagsDefaultOff() throws {
        let command = try DumpCommand.parse(["/tmp/example"])
        #expect(command.emitHeader == false)
        #expect(command.emitExportStatus == false)
    }

    @Test func dumpFlagsParse() throws {
        let command = try DumpCommand.parse(["/tmp/example", "--emit-header", "--emit-export-status"])
        #expect(command.emitHeader == true)
        #expect(command.emitExportStatus == true)
    }
}
