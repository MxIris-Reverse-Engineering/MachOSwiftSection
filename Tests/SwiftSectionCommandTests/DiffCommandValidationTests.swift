import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Pins `swift-section diff`'s `--jobs` option (evolution proposal
/// `large-stack-executor-and-cross-version-parallelism`): the two sides index
/// concurrently by default, `--jobs 1` restores the old-then-new order, and a
/// window below 1 is rejected at validation time rather than clamped silently
/// — on the command line a zero is a typo, not a request.
@Suite
struct DiffCommandValidationTests {
    private func expectValidationFailure(_ arguments: [String], messagePart: String) {
        #expect(
            "parsing \(arguments) should fail validation",
            performing: {
                _ = try DiffCommand.parse(arguments)
            },
            throws: { error in
                DiffCommand.message(for: error).contains(messagePart)
            }
        )
    }

    @Test func jobsBelowOneIsRejected() {
        expectValidationFailure(
            ["--jobs", "0", "old.dylib", "new.dylib"],
            messagePart: "--jobs must be at least 1"
        )
    }

    @Test func jobsParsesAndDefaultsToAbsent() throws {
        let explicit = try DiffCommand.parse(["--jobs", "1", "old.dylib", "new.dylib"])
        #expect(explicit.jobs == 1)
        let implicit = try DiffCommand.parse(["old.dylib", "new.dylib"])
        #expect(implicit.jobs == nil)
    }

    @Test func jobsParsesAlongsideTheInterfaceOptions() throws {
        let command = try DiffCommand.parse(["--interface", "--format", "unified", "--jobs", "2", "old.dylib", "new.dylib"])
        #expect(command.interface)
        #expect(command.format == .unified)
        #expect(command.jobs == 2)
    }
}
