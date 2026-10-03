import ArgumentParser
import Foundation
import SwiftSectionKit

struct ObjCEvolutionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "evolution",
        abstract: "Track the ObjC API of one binary across an ordered series of versions.",
        discussion: """
        Pass two or more inputs in version order (oldest first). Each input is either a \
        Mach-O / fat binary, a dyld shared cache (with --dyld-shared-cache, extracting the \
        same image from every cache), or a baseline snapshot produced by `swift-section objc snapshot`.
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

    @Option(name: [.long, .customShort("n")], help: "Image name to extract from each dyld shared cache (e.g. AppKit).")
    var cacheImageName: String?

    @Option(name: [.long, .customShort("p")], help: "Image path to extract from each dyld shared cache.")
    var cacheImagePath: String?

    @Flag(help: "Print only the header and per-transition summary, not the full lineage report.")
    var summaryOnly: Bool = false

    @Flag(help: "Emit the evolution as JSON instead of the text report.")
    var json: Bool = false

    @Flag(help: "Exit with a nonzero status when any transition contains an API-breaking change, for CI gating.")
    var failOnBreaking: Bool = false

    @Option(name: .shortAndLong, help: "Write the report to this path instead of stdout.", completion: .file())
    var outputPath: String?

    /// The library request these flags describe.
    func makeRequest() -> ObjCAPIEvolutionRequest {
        let report: ObjCAPIEvolutionRequest.Report = if json {
            .json
        } else if summaryOnly {
            .summary
        } else {
            .lineage
        }
        // validate() has already required exactly one of -n / -p with
        // --dyld-shared-cache.
        let cacheImage: DyldSharedCacheImage? = cacheImageName.map { .name($0) } ?? cacheImagePath.map { .path($0) }
        return ObjCAPIEvolutionRequest(
            inputs: inputPaths.map { .path($0) },
            labels: labels.map(EvolutionCommand.splitLabels),
            binaryLoading: BinaryLoadingOptions(
                architecture: architecture,
                dyldSharedCacheImage: isDyldSharedCache ? cacheImage : nil
            ),
            report: report,
            destination: outputPath.map { .file(path: $0) } ?? .output
        )
    }

    func run() async throws {
        let outcome: ObjCAPIEvolutionOutcome
        do {
            outcome = try await makeRequest().run(output: StandardStreamOutput(), environment: .commandLine)
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
        if failOnBreaking, outcome.hasBreakingChange {
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
}
