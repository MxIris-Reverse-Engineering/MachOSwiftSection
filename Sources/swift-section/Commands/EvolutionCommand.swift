import ArgumentParser
import Foundation
import SwiftDiffing

struct EvolutionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "evolution",
        abstract: "Track the Swift ABI of one module across an ordered series of binary versions.",
        discussion: """
        Pass two or more inputs in version order (oldest first). Each input is either a \
        Mach-O / fat binary, a dyld shared cache (with --dyld-shared-cache, extracting the \
        same image from every cache), or a baseline snapshot produced by `swift-section snapshot`.
        """
    )

    @Argument(help: "The input paths in version order (oldest first); Mach-O binaries, dyld shared caches, or snapshot JSON files.", completion: .file())
    var inputPaths: [String]

    @Option(name: .long, help: "Comma-separated version labels for the axis (e.g. 17.0,18.0,26.0); one per input. Defaults to each snapshot's stored label or the input's file name.")
    var labels: String?

    @Option(name: .shortAndLong, help: "The architecture slice to use for fat binaries. Required when any input is a fat (universal) binary.")
    var architecture: Architecture?

    @Flag(name: [.customLong("dyld-shared-cache")], help: "Treat every binary input as a dyld shared cache and extract the same image (--cache-image-name) from each.")
    var isDyldSharedCache: Bool = false

    @Option(name: [.long, .customShort("n")], help: "Image name to extract from each dyld shared cache (e.g. SwiftUICore).")
    var cacheImageName: String?

    @Option(name: [.long, .customShort("p")], help: "Image path to extract from each dyld shared cache.")
    var cacheImagePath: String?

    @Flag(help: "Print only the header and per-transition summary, not the full lineage report.")
    var summaryOnly: Bool = false

    @Flag(help: "Emit the evolution as JSON instead of the text report.")
    var json: Bool = false

    @Flag(help: "Exit with a nonzero status when any transition contains an ABI-breaking change, for CI gating.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        let explicitLabels = try ABISnapshotInputLoader.parseLabels(labels, inputCount: inputPaths.count)

        var documents: [ABISnapshotDocument] = []
        for (index, inputPath) in inputPaths.enumerated() {
            let document = try await ABISnapshotInputLoader.loadDocument(
                path: inputPath,
                architecture: architecture,
                isDyldSharedCache: isDyldSharedCache,
                cacheImageName: cacheImageName,
                cacheImagePath: cacheImagePath,
                label: explicitLabels[index],
                log: log
            )
            documents.append(document)
        }

        // Snapshot inputs may already carry a provenance label; binaries fall
        // back to their file name so the axis is always readable.
        let resolvedLabels = documents.enumerated().map { index, document in
            document.provenance?.label ?? ABISnapshotInputLoader.defaultLabel(forPath: inputPaths[index])
        }

        log("Tracking evolution…")
        let evolution = try ABIEvolutionBuilder().evolution(of: documents, labels: resolvedLabels)

        let output: String
        if json {
            output = String(decoding: try ABIJSON.encoder().encode(evolution), as: UTF8.self)
        } else if summaryOnly {
            output = ABIEvolutionReporter().summary(evolution)
        } else {
            output = ABIEvolutionReporter().report(evolution)
        }
        if let outputPath {
            try (output + "\n").write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Report written to \(outputPath)")
        } else {
            print(output)
        }

        if failOnBreaking, evolution.hasBreakingChange {
            throw ExitCode.failure
        }
    }

    /// Rejects flag combinations that would otherwise be silently ignored, so
    /// the user gets immediate feedback instead of a no-op.
    func validate() throws {
        if inputPaths.count < 2 {
            throw ValidationError("evolution needs at least 2 inputs in version order (oldest first).")
        }
        if json, summaryOnly {
            throw ValidationError("--json and --summary-only are mutually exclusive.")
        }
        if cacheImageName != nil, cacheImagePath != nil {
            throw ValidationError("--cache-image-name and --cache-image-path are mutually exclusive; pass only one.")
        }
        if cacheImageName != nil || cacheImagePath != nil, !isDyldSharedCache {
            throw ValidationError("--cache-image-name / --cache-image-path require --dyld-shared-cache.")
        }
        if isDyldSharedCache, cacheImageName == nil, cacheImagePath == nil {
            throw ValidationError("--dyld-shared-cache requires --cache-image-name or --cache-image-path.")
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
