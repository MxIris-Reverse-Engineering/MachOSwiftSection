import Foundation
import ArgumentParser
import MachOFixtureSupport

struct BaselineGeneratorMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline-generator",
        abstract: "Regenerates ABI baselines for MachOSwiftSection fixture tests."
    )

    @Option(
        name: .long,
        help: "Output directory for baseline files. Defaults to Tests/MachOSwiftSectionTests/Fixtures/__Baseline__."
    )
    var output: String = "Tests/MachOSwiftSectionTests/Fixtures/__Baseline__"

    @Option(
        name: .long,
        help: "Restrict regeneration to a specific Suite, e.g. StructDescriptor. If omitted, regenerates all baselines."
    )
    var suite: String?

    func run() async throws {
        let outputURL = URL(fileURLWithPath: output)
        if let suite {
            try await BaselineGenerator.generate(suite: suite, outputDirectory: outputURL)
        } else {
            try await BaselineGenerator.generateAll(outputDirectory: outputURL)
        }
    }
}
