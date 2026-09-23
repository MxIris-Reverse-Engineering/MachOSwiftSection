import ArgumentParser
import Foundation
import ObjCDiffing

struct ObjCDiffCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "diff",
        abstract: "Diff the ObjC API of two Mach-O binaries (or persisted baseline snapshots)."
    )

    @Argument(help: "The old (baseline) side: a Mach-O file path or a snapshot JSON produced by `swift-section objc snapshot`.", completion: .file())
    var oldPath: String

    @Argument(help: "The new side: a Mach-O file path or a snapshot JSON.", completion: .file())
    var newPath: String

    @Option(name: .shortAndLong, help: "The architecture slice to use for fat binaries. Required when either path is a fat (universal) binary.")
    var architecture: Architecture?

    @Flag(name: [.customLong("dyld-shared-cache")], help: "Treat both paths as dyld shared caches and extract the same image (--cache-image-name) from each.")
    var isDyldSharedCache: Bool = false

    @Option(name: [.long, .customShort("n")], help: "Image name to extract from each dyld shared cache (e.g. AppKit).")
    var cacheImageName: String?

    @Option(name: [.long, .customShort("p")], help: "Image path to extract from each dyld shared cache.")
    var cacheImagePath: String?

    @Flag(help: "Print only the breaking/backward-compatible verdict, not the full report.")
    var summaryOnly: Bool = false

    @Flag(help: "Emit the API diff as JSON (with provenance) instead of the text report.")
    var json: Bool = false

    @Flag(help: "Exit with a nonzero status when the diff contains an API-breaking change, for CI gating.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        let oldDocument = try await loadDocument(at: oldPath)
        let newDocument = try await loadDocument(at: newPath)

        log("Diffing…")
        let diff = ObjCAPIDiffer().diff(old: oldDocument, new: newDocument)

        let verdict = "API-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        if json {
            let encoded = String(decoding: try ObjCAPIJSON.encoder().encode(diff), as: UTF8.self)
            try emit(encoded)
        } else if summaryOnly {
            print(verdict)
        } else {
            try emit(ObjCAPIDiffReporter().report(diff) + "\n\n" + verdict)
        }

        if failOnBreaking, diff.hasBreakingChange {
            throw ExitCode.failure
        }
    }

    /// Rejects flag combinations that would otherwise be silently ignored, so
    /// the user gets immediate feedback instead of a no-op.
    func validate() throws {
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

    /// Loads one input: a snapshot JSON is decoded, a binary is indexed and
    /// frozen (with provenance stamped).
    private func loadDocument(at path: String) async throws -> ObjCAPISnapshotDocument {
        try await ObjCSnapshotInputLoader.loadDocument(
            path: path,
            architecture: architecture,
            isDyldSharedCache: isDyldSharedCache,
            cacheImageName: cacheImageName,
            cacheImagePath: cacheImagePath,
            label: nil,
            log: log
        )
    }

    /// Writes a report to `--output` or stdout.
    private func emit(_ text: String) throws {
        if let outputPath {
            try text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Report written to \(outputPath)")
        } else {
            print(text)
        }
    }

    private func log(_ message: String) {
        writeStandardErrorLine(message)
    }
}
