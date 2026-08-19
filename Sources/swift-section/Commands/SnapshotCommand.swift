import ArgumentParser
import Foundation
import SwiftDiffing

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "snapshot",
        abstract: "Index a Mach-O binary's Swift ABI and persist it as a baseline snapshot (JSON)."
    )

    @OptionGroup var machOOptions: MachOOptionGroup

    @Option(name: .long, help: "A human-readable version label stored in the snapshot's provenance (e.g. 17.0).")
    var label: String?

    @Option(name: .shortAndLong, help: "Write the snapshot JSON to this path instead of stdout.", completion: .file())
    var outputPath: String?

    func run() async throws {
        guard let filePath = machOOptions.filePath else {
            throw ValidationError("A Mach-O file path is required.")
        }
        let document = try await ABISnapshotInputLoader.loadDocument(
            path: filePath,
            architecture: machOOptions.architecture,
            isDyldSharedCache: machOOptions.isDyldSharedCache,
            cacheImageName: machOOptions.cacheImageName,
            cacheImagePath: machOOptions.cacheImagePath,
            label: label,
            log: log
        )
        let encoded = try document.encoded()
        if let outputPath {
            try encoded.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            log("Snapshot written to \(outputPath)")
        } else {
            // `fwrite`, not `FileHandle.standardOutput.write(_:)`. This is the
            // command's product output, not a diagnostic, but it took the same
            // raising Objective-C overload — so `swift-section snapshot … | head`
            // aborted the process rather than stopping cleanly.
            // `write(contentsOf:)` would be the throwing Swift spelling, but it
            // needs macOS 10.15.4 and this package deploys to 10.15.
            encoded.withUnsafeBytes { buffer in
                _ = fwrite(buffer.baseAddress, 1, buffer.count, stdout)
            }
            fputs("\n", stdout)
        }
    }

    func validate() throws {
        if machOOptions.usesSystemDyldSharedCache {
            // A snapshot of "the current system cache" would have no stable
            // path to record; require an explicit cache file for baselines.
            throw ValidationError("snapshot requires an explicit file path; --uses-system-dyld-shared-cache is not supported here.")
        }
    }

    private func log(_ message: String) {
        // See `DiffCommand.log`: the raising `FileHandle` overload aborts the
        // process on a closed or broken stderr.
        fputs(message + "\n", stderr)
    }
}
