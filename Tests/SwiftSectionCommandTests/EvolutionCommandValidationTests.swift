import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Pins `swift-section evolution`'s flag-validation rules around the annotated
/// interface: `--interface` is mutually exclusive with the other output modes,
/// and the pre-existing rules keep holding with the new flag present.
@Suite
struct EvolutionCommandValidationTests {
    private func expectValidationFailure(_ arguments: [String], messagePart: String) {
        #expect(
            "parsing \(arguments) should fail validation",
            performing: {
                _ = try EvolutionCommand.parse(arguments)
            },
            throws: { error in
                EvolutionCommand.message(for: error).contains(messagePart)
            }
        )
    }

    @Test func interfaceAndJSONAreMutuallyExclusive() {
        expectValidationFailure(
            ["--interface", "--json", "old.dylib", "new.dylib"],
            messagePart: "--json and --interface are mutually exclusive"
        )
    }

    @Test func interfaceAndSummaryOnlyAreMutuallyExclusive() {
        expectValidationFailure(
            ["--interface", "--summary-only", "old.dylib", "new.dylib"],
            messagePart: "--interface and --summary-only are mutually exclusive"
        )
    }

    @Test func interfaceStillRequiresTwoInputs() {
        expectValidationFailure(
            ["--interface", "only.dylib"],
            messagePart: "at least 2 inputs"
        )
    }

    @Test func interfaceParsesAlongsideTheSharedOptions() throws {
        let command = try EvolutionCommand.parse([
            "--interface", "--labels", "1.0,2.0", "--fail-on-breaking", "old.dylib", "new.dylib",
        ])
        #expect(command.interface)
        #expect(command.failOnBreaking)
        #expect(command.inputPaths == ["old.dylib", "new.dylib"])
    }
}
