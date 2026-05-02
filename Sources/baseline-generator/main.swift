import Foundation
import ArgumentParser
import MachOTestingSupport

/// Phase-1 stub: invokes BaselineGenerator.generateAll(); proper CLI in Task 17.
///
/// The current working directory at invocation time is the package root, so
/// the output URL is package-relative.
@main
struct BaselineGeneratorMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline-generator",
        abstract: "Regenerates fixture-based test baselines under Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/."
    )

    func run() async throws {
        let outputDirectory = URL(fileURLWithPath: "Tests/MachOSwiftSectionTests/Fixtures/__Baseline__")
        try await BaselineGenerator.generateAll(outputDirectory: outputDirectory)
    }
}
