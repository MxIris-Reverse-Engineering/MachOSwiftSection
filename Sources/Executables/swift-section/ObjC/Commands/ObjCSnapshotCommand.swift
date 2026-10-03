import ArgumentParser
import Foundation
import SwiftSectionKit

struct ObjCSnapshotCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "snapshot",
        abstract: "Index a Mach-O binary's ObjC API and persist it as a baseline snapshot (JSON)."
    )

    @OptionGroup var machOOptions: ObjCMachOOptionGroup

    @Option(name: .long, help: "A human-readable version label stored in the snapshot's provenance (e.g. 26.0).")
    var label: String?

    @Option(name: .shortAndLong, help: "Write the snapshot JSON to this path instead of stdout.", completion: .file())
    var outputPath: String?

    /// The library request these flags describe.
    func makeRequest() throws -> ObjCAPISnapshotRequest {
        guard let filePath = machOOptions.filePath else {
            throw ValidationError("A Mach-O file path is required.")
        }
        return ObjCAPISnapshotRequest(
            source: .path(filePath),
            binaryLoading: try makeBinaryLoadingOptions(
                isDyldSharedCache: machOOptions.isDyldSharedCache,
                cacheImageName: machOOptions.cacheImageName,
                cacheImagePath: machOOptions.cacheImagePath,
                architecture: machOOptions.architecture
            ),
            label: label,
            destination: outputPath.map { .file(path: $0) } ?? .output
        )
    }

    func run() async throws {
        let request = try makeRequest()
        do {
            try await request.run(output: StandardStreamOutput(), environment: .commandLine)
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }

    func validate() throws {
        if machOOptions.usesSystemDyldSharedCache {
            // A snapshot of "the current system cache" would have no stable
            // path to record; require an explicit cache file for baselines.
            throw ValidationError("snapshot requires an explicit file path; --uses-system-dyld-shared-cache is not supported here.")
        }
    }
}
