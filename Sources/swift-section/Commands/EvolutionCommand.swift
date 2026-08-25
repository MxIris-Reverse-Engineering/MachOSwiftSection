import ArgumentParser
import Foundation
import SwiftDiffing
import SwiftInterface
import SwiftIndexing
import MachOKit
import MachOFoundation
import Rainbow

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

    @Flag(help: "Emit the union Swift interface annotated with per-declaration lifecycle comments instead of the lineage report. Every input must be a binary (or dyld shared cache); snapshot JSON inputs are rejected.")
    var interface: Bool = false

    @Flag(help: "Exit with a nonzero status when any transition contains an ABI-breaking change, for CI gating.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        let explicitLabels = try ABISnapshotInputLoader.parseLabels(labels, inputCount: inputPaths.count)

        if interface {
            try await runAnnotatedInterface(explicitLabels: explicitLabels)
            return
        }

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

    /// The `--interface` path: render the union interface with lifecycle
    /// annotations from N live binaries. The annotated interface renders from
    /// the live models, so every input must be a binary — a persisted snapshot
    /// carries no renderable interface (same constraint as `diff --interface`).
    private func runAnnotatedInterface(explicitLabels: [String?]) async throws {
        for inputPath in inputPaths {
            if try ABISnapshotInputLoader.isSnapshotDocument(atPath: inputPath) {
                throw ValidationError("--interface needs binaries; snapshot JSON inputs (\(inputPath)) only support the lineage report.")
            }
        }

        var machOFiles: [MachOFile] = []
        for inputPath in inputPaths {
            log("Loading \(inputPath)…")
            machOFiles.append(try loadMachO(at: inputPath))
        }
        let resolvedLabels = inputPaths.enumerated().map { index, inputPath in
            explicitLabels[index] ?? ABISnapshotInputLoader.defaultLabel(forPath: inputPath)
        }

        // A sink on every version: each version's builder hands this handler to
        // its indexer AND printer, so a dropped declaration lands on stderr
        // instead of the os_log floor a CLI operator never sees.
        let builder = try SwiftEvolutionInterfaceBuilder(
            eventHandlers: [ConsoleEventHandler()],
            versions: machOFiles,
            labels: resolvedLabels
        )
        log("Indexing \(machOFiles.count) versions…")
        try await builder.prepare()
        log("Rendering annotated interface…")
        let annotated = try await builder.printAnnotatedInterface()
        try emitInterface(annotated.string)

        if failOnBreaking, let evolution = builder.evolution, evolution.hasBreakingChange {
            throw ExitCode.failure
        }
    }

    /// Loads one `--interface`-path input: an image extracted from a dyld
    /// shared cache, or a thin/fat file on disk — the same shared
    /// `MachOFile.load(...)` the rest of the CLI uses (see `DiffCommand`).
    private func loadMachO(at path: String) throws -> MachOFile {
        try MachOFile.load(
            filePath: path,
            isDyldSharedCache: isDyldSharedCache,
            usesSystemDyldSharedCache: false,
            cacheImageName: cacheImageName,
            cacheImagePath: cacheImagePath,
            architecture: architecture
        )
    }

    /// Writes the annotated interface: plain text to `--output`, or per-line
    /// colorized to the terminal — legend/warning comments cyan, and each
    /// annotated line colored by its most severe lifecycle event (removed red,
    /// modified yellow, added green).
    private func emitInterface(_ text: String) throws {
        if let outputPath {
            try text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Annotated interface written to \(outputPath)")
            return
        }
        var output = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            if lineText.hasPrefix("//") {
                // Legend and warnings blocks sit at column 0.
                output += lineText.cyan
            } else if let annotationRange = lineText.range(of: "// [") {
                // A trailing lifecycle annotation, or an overflow annotation on
                // its own (indented) line. Classify by the annotation text only
                // so a declaration whose name mentions these words stays plain.
                let annotation = lineText[annotationRange.lowerBound...]
                if annotation.contains("removed in") {
                    output += lineText.red
                } else if annotation.contains("modified in") {
                    output += lineText.yellow
                } else {
                    output += lineText.green
                }
            } else {
                output += lineText
            }
            output += "\n"
        }
        print(output, terminator: "")
    }

    /// Rejects flag combinations that would otherwise be silently ignored, so
    /// the user gets immediate feedback instead of a no-op.
    func validate() throws {
        if interface, json {
            throw ValidationError("--json and --interface are mutually exclusive.")
        }
        if interface, summaryOnly {
            throw ValidationError("--interface and --summary-only are mutually exclusive.")
        }
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
        // See `DiffCommand.log`: the raising `FileHandle` overload aborts the
        // process on a closed or broken stderr.
        fputs(message + "\n", stderr)
    }
}
