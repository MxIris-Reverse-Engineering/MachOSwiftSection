import SwiftInterface
import SwiftDiffing
import Foundation
import MachOKit
import MachOFoundation
import ArgumentParser
import Rainbow

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

    @Flag(help: "Emit the full Swift interface annotated with inline +/- markers (git-diff style) instead of the change-list.")
    var interface: Bool = false

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

        if interface {
            log("Rendering annotated interface…")
            let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
            let annotated = await renderer.printAnnotatedInterface()
            try emit(annotated.string)
            return
        }

        log("Diffing…")
        let diff = ABIDiffer().diff(old: oldBuilder.abiModule(), new: newBuilder.abiModule())

        let verdict = "ABI-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"

        if summaryOnly {
            print(verdict)
            return
        }

        let report = ABIDiffReporter().report(diff) + "\n\n" + verdict
        if let outputPath {
            try report.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Report written to \(outputPath)")
        } else {
            print(report)
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
                guard let image = try cache.machOFile(by: .path(cacheImagePath)) else {
                    throw SwiftSectionCommandError.imageNotFound
                }
                return image
            }
            guard let cacheImageName else {
                throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
            }
            guard let image = try cache.machOFile(by: .name(cacheImageName)) else {
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

    /// Writes the annotated interface: plain text to `--output`, or git-diff-style
    /// per-line colorized (added green, removed red) to the terminal.
    private func emit(_ text: String) throws {
        if let outputPath {
            try text.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            log("Annotated interface written to \(outputPath)")
            return
        }
        var output = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+") {
                output += String(line).green
            } else if line.hasPrefix("-") {
                output += String(line).red
            } else {
                output += String(line)
            }
            output += "\n"
        }
        print(output, terminator: "")
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
