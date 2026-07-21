import SwiftInterface
import SwiftDiffing
import Foundation
import MachOKit
import MachOFoundation
import ArgumentParser
import Rainbow

/// The output format for the annotated interface (`--interface`).
enum DiffOutputFormat: String, CaseIterable, ExpressibleByArgument {
    /// git-diff-style `+`/`-`/` ` line prefixes (the default).
    case inline
    /// A real unified diff (`--- old`/`+++ new` + `@@` hunks), consumable by
    /// `git apply` / `patch` / `delta`.
    case unified
    /// The inline body wrapped in a Markdown ```` ```diff ```` fence.
    case markdown
}

struct DiffCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "diff",
        abstract: "Diff the Swift ABI of two Mach-O binaries (or persisted baseline snapshots)."
    )

    @Argument(help: "The old (baseline) side: a Mach-O file path or a snapshot JSON produced by `swift-section snapshot`.", completion: .file())
    var oldPath: String

    @Argument(help: "The new side: a Mach-O file path or a snapshot JSON.", completion: .file())
    var newPath: String

    @Option(name: .shortAndLong, help: "The architecture slice to use for fat binaries. Required when either path is a fat (universal) binary.")
    var architecture: Architecture?

    @Flag(name: [.customLong("dyld-shared-cache")], help: "Treat both paths as dyld shared caches and extract the same image (--cache-image-name) from each.")
    var isDyldSharedCache: Bool = false

    @Option(name: [.long, .customShort("n")], help: "Image name to extract from each dyld shared cache (e.g. SwiftUICore).")
    var cacheImageName: String?

    @Option(name: [.long, .customShort("p")], help: "Image path to extract from each dyld shared cache.")
    var cacheImagePath: String?

    @Flag(help: "Print only the breaking/backward-compatible verdict, not the full report.")
    var summaryOnly: Bool = false

    @Flag(help: "Emit the ABI diff as JSON (with provenance) instead of the text report.")
    var json: Bool = false

    @Flag(help: "Emit the full Swift interface annotated with diff markers instead of the change-list.")
    var interface: Bool = false

    @Option(name: .long, help: "Annotated-interface format: inline (git-diff style), unified (real unified diff), or markdown (```diff fence). Requires --interface; defaults to inline.")
    var format: DiffOutputFormat?

    @Flag(help: "Exit with a nonzero status when the diff contains an ABI-breaking change, for CI gating. Honored with --interface too.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        let abiDiff: ABIDiff?
        if interface {
            // The annotated interface renders from the live models, so both
            // sides must be binaries — a persisted snapshot carries no
            // renderable interface.
            if try ABISnapshotInputLoader.isSnapshotDocument(atPath: oldPath)
                || ABISnapshotInputLoader.isSnapshotDocument(atPath: newPath) {
                throw ValidationError("--interface needs two binaries; snapshot JSON inputs only support the change-list report.")
            }

            let oldMachO = try loadMachO(at: oldPath)
            let newMachO = try loadMachO(at: newPath)

            log("Indexing old binary…")
            let oldBuilder = SwiftDiffableInterfaceBuilder(in: oldMachO)
            try await oldBuilder.prepare()

            log("Indexing new binary…")
            let newBuilder = SwiftDiffableInterfaceBuilder(in: newMachO)
            try await newBuilder.prepare()

            // Only the `--fail-on-breaking` CI gate needs the ABI diff on the
            // annotated-interface path.
            abiDiff = failOnBreaking
                ? ABIDiffer().diff(old: oldBuilder.abiModule(), new: newBuilder.abiModule())
                : nil

            log("Rendering annotated interface…")
            let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
            let diffFormat: DiffFormat
            switch format ?? .inline {
            case .inline:
                diffFormat = .inline
            case .unified:
                diffFormat = .unified(oldLabel: oldPath, newLabel: newPath)
            case .markdown:
                diffFormat = .markdownFenced
            }
            let annotated = await renderer.printAnnotatedInterface(format: diffFormat)
            try emit(annotated.string)
        } else {
            // The change-list path is snapshot-based either way, so each side
            // may be a binary (indexed and frozen here) or a persisted
            // baseline (decoded, with its format version validated).
            let oldDocument = try await loadDocument(at: oldPath)
            let newDocument = try await loadDocument(at: newPath)

            log("Diffing…")
            let diff = ABIDiffer().diff(old: oldDocument, new: newDocument)
            abiDiff = diff

            let verdict = "ABI-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
            if json {
                let encoded = String(decoding: try ABIJSON.encoder().encode(diff), as: UTF8.self)
                try emitPlain(encoded)
            } else if summaryOnly {
                print(verdict)
            } else {
                try emitPlain(ABIDiffReporter().report(diff) + "\n\n" + verdict)
            }
        }

        if failOnBreaking, let abiDiff, abiDiff.hasBreakingChange {
            throw ExitCode.failure
        }
    }

    /// Rejects flag combinations that would otherwise be silently ignored, so the
    /// user gets immediate feedback instead of a no-op.
    func validate() throws {
        if interface, summaryOnly {
            throw ValidationError("--interface and --summary-only are mutually exclusive.")
        }
        if json, interface {
            throw ValidationError("--json and --interface are mutually exclusive.")
        }
        if json, summaryOnly {
            throw ValidationError("--json and --summary-only are mutually exclusive.")
        }
        if format != nil, !interface {
            throw ValidationError("--format only applies to the annotated interface; pass --interface.")
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

    /// Loads a Mach-O for diffing: either an image extracted from a dyld shared
    /// cache (so cross-image references into Foundation/libswiftCore resolve), or
    /// a thin/fat file on disk. Both sides go through the shared
    /// `MachOFile.load(...)` so the fat-binary affordance and cache-image
    /// disambiguation match the rest of the CLI. `--dyld-shared-cache` here means
    /// "treat each path as a cache and pull the same image from both", so the
    /// system-cache path is never taken.
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

    /// Loads one change-list-path input: a snapshot JSON is decoded, a binary
    /// is indexed and frozen (with provenance stamped).
    private func loadDocument(at path: String) async throws -> ABISnapshotDocument {
        try await ABISnapshotInputLoader.loadDocument(
            path: path,
            architecture: architecture,
            isDyldSharedCache: isDyldSharedCache,
            cacheImageName: cacheImageName,
            cacheImagePath: cacheImagePath,
            label: nil,
            log: log
        )
    }

    /// Writes an uncolorized report to `--output` or stdout.
    private func emitPlain(_ text: String) throws {
        if let outputPath {
            try text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Report written to \(outputPath)")
        } else {
            print(text)
        }
    }

    /// Writes the annotated interface: plain text to `--output`, or per-line
    /// colorized (added green, removed red) to the terminal.
    private func emit(_ text: String) throws {
        if let outputPath {
            try text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Annotated interface written to \(outputPath)")
            return
        }
        var output = ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let lineText = String(line)
            // In a unified diff the first two lines are the `--- old` / `+++ new`
            // file headers and `@@ … @@` lines are hunk headers; colorize those by
            // position / prefix so an added/removed content line that happens to
            // begin with `++` or `--` is never mistaken for a file header.
            if format == .unified, index < 2 {
                output += lineText.cyan
            } else if format == .unified, lineText.hasPrefix("@@") {
                output += lineText.cyan
            } else if lineText.hasPrefix("+") {
                output += lineText.green
            } else if lineText.hasPrefix("-") {
                output += lineText.red
            } else {
                output += lineText
            }
            output += "\n"
        }
        print(output, terminator: "")
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
