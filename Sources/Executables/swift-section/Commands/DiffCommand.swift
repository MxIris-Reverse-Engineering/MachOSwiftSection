import Foundation
import ArgumentParser
import SwiftSectionKit

/// The output format for the annotated interface (`--interface`).
enum DiffOutputFormat: String, CaseIterable, ExpressibleByArgument {
    /// git-diff-style `+`/`-`/` ` line prefixes (the default).
    case inline
    /// A real unified diff (`--- old`/`+++ new` + `@@` hunks), consumable by
    /// `git apply` / `patch` / `delta`.
    case unified
    /// The inline body wrapped in a Markdown ```` ```diff ```` fence.
    case markdown

    var annotatedDiffFormat: AnnotatedDiffFormat {
        switch self {
        case .inline:
            .inline
        case .unified:
            .unified
        case .markdown:
            .markdownFenced
        }
    }
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

    @Option(name: .long, help: "How many inputs to index at once (default: the processor count). Pass 1 to index the old side, then the new side.")
    var jobs: Int?

    /// The library request these flags describe.
    func makeRequest() -> ABIDiffRequest {
        let report: ABIDiffRequest.Report
        if interface {
            report = .annotatedInterface(
                format: (format ?? .inline).annotatedDiffFormat,
                // Only the `--fail-on-breaking` CI gate needs the change-list
                // diff on the annotated-interface path.
                includesBreakingChangeVerdict: failOnBreaking
            )
        } else if json {
            report = .json
        } else if summaryOnly {
            report = .summary
        } else {
            report = .changeList
        }
        // validate() has already required exactly one of -n / -p with
        // --dyld-shared-cache.
        let cacheImage: DyldSharedCacheImage? = cacheImageName.map { .name($0) } ?? cacheImagePath.map { .path($0) }
        return ABIDiffRequest(
            old: .path(oldPath),
            new: .path(newPath),
            binaryLoading: BinaryLoadingOptions(
                architecture: architecture,
                dyldSharedCacheImage: isDyldSharedCache ? cacheImage : nil
            ),
            report: report,
            destination: outputPath.map { .file(path: $0) } ?? .output,
            maximumConcurrentPreparations: jobs
        )
    }

    func run() async throws {
        let outcome: ABIDiffOutcome
        do {
            outcome = try await makeRequest().run(output: StandardStreamOutput(), environment: .commandLine)
        } catch {
            throw CommandLineErrorTranslation.translated(error, annotatedInterfaceRequiresBinaries: { _ in
                "--interface needs two binaries; snapshot JSON inputs only support the change-list report."
            })
        }
        if failOnBreaking, outcome.hasBreakingChange == true {
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
        if let jobs, jobs < 1 {
            throw ValidationError("--jobs must be at least 1.")
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
}
