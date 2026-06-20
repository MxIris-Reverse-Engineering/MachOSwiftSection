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
        abstract: "Diff the Swift ABI of two Mach-O binaries."
    )

    @Argument(help: "The old (baseline) Mach-O file path.", completion: .file())
    var oldPath: String

    @Argument(help: "The new Mach-O file path.", completion: .file())
    var newPath: String

    @Option(name: .shortAndLong, help: "The architecture slice to use for fat binaries.")
    var architecture: Architecture = .arm64

    @Flag(name: [.customLong("dyld-shared-cache")], help: "Treat both paths as dyld shared caches and extract the same image (--cache-image-name) from each.")
    var isDyldSharedCache: Bool = false

    @Option(name: [.long, .customShort("n")], help: "Image name to extract from each dyld shared cache (e.g. SwiftUICore).")
    var cacheImageName: String?

    @Option(name: [.long, .customShort("p")], help: "Image path to extract from each dyld shared cache.")
    var cacheImagePath: String?

    @Flag(help: "Print only the breaking/backward-compatible verdict, not the full report.")
    var summaryOnly: Bool = false

    @Flag(help: "Emit the full Swift interface annotated with diff markers instead of the change-list.")
    var interface: Bool = false

    @Option(name: .long, help: "Annotated-interface format: inline (git-diff style), unified (real unified diff), or markdown (```diff fence). Requires --interface; defaults to inline.")
    var format: DiffOutputFormat?

    @Flag(help: "Exit with a nonzero status when the diff contains an ABI-breaking change, for CI gating. Honored with --interface too.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        let oldMachO = try loadMachO(at: oldPath)
        let newMachO = try loadMachO(at: newPath)

        log("Indexing old binary…")
        let oldBuilder = SwiftDiffableInterfaceBuilder(in: oldMachO)
        try await oldBuilder.prepare()

        log("Indexing new binary…")
        let newBuilder = SwiftDiffableInterfaceBuilder(in: newMachO)
        try await newBuilder.prepare()

        // The change-list report and the `--fail-on-breaking` CI gate both need
        // the ABI diff; the annotated-interface path does not, so compute it only
        // when one of those actually requires it.
        let abiDiff = (!interface || failOnBreaking)
            ? ABIDiffer().diff(old: oldBuilder.abiModule(), new: newBuilder.abiModule())
            : nil

        if interface {
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
        } else if let abiDiff {
            log("Diffing…")
            let verdict = "ABI-breaking: \(abiDiff.hasBreakingChange) · backward-compatible: \(abiDiff.isBackwardCompatible)"
            if summaryOnly {
                print(verdict)
            } else {
                let report = ABIDiffReporter().report(abiDiff) + "\n\n" + verdict
                if let outputPath {
                    try report.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
                    log("Report written to \(outputPath)")
                } else {
                    print(report)
                }
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
    /// a thin/fat file on disk (selecting the requested architecture slice).
    private func loadMachO(at path: String) throws -> MachOFile {
        let url = URL(fileURLWithPath: path)

        if isDyldSharedCache {
            let cache = try DyldCache(url: url)
            if let cacheImagePath {
                guard let image = cache.machOFile(by: .path(cacheImagePath)) else {
                    throw SwiftSectionCommandError.imageNotFound
                }
                return image
            }
            guard let cacheImageName else {
                throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
            }
            guard let image = cache.machOFile(by: .name(cacheImageName)) else {
                throw SwiftSectionCommandError.imageNotFound
            }
            return image
        }

        switch try File.loadFromFile(url: url) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFiles = try fatFile.machOFiles()
            guard let slice = machOFiles.first(where: { $0.header.cpu.subtype == architecture.cpu }) else {
                throw SwiftSectionCommandError.invalidArchitecture
            }
            return slice
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
