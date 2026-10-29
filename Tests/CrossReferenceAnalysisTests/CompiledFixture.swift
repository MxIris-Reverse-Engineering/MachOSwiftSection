import Foundation
import MachOKit

/// A dynamic library compiled from source for one suite, rewritten after
/// linking when the suite asks, and loaded into the test process.
enum CompiledFixture {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Compiles `sources` — file names and their contents — into the arm64
    /// library `libraryName`, hands the linked bytes to `rewrite` and signs
    /// the result again when there is one, and loads it. The library stays
    /// loaded after its directory is removed; the analyzers made from then on
    /// see it under the path this returns.
    @discardableResult
    static func load(
        libraryName: String,
        sources: KeyValuePairs<String, String>,
        compilerArguments: [String],
        rewrite: ((inout Data, MachOFile) throws -> Void)? = nil
    ) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrossReferenceAnalysisTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var sourcePaths: [String] = []
        for (fileName, contents) in sources {
            let sourceURL = directory.appendingPathComponent(fileName)
            try contents.write(to: sourceURL, atomically: true, encoding: .utf8)
            sourcePaths.append(sourceURL.path)
        }
        let library = directory.appendingPathComponent(libraryName)
        try run("/usr/bin/xcrun", arguments: ["clang", "-dynamiclib", "-arch", "arm64"] + compilerArguments + ["-o", library.path] + sourcePaths)
        if let rewrite {
            var bytes = try Data(contentsOf: library)
            try rewrite(&bytes, try MachOFile(url: library))
            try bytes.write(to: library)
            // Rewritten code no longer matches the signature's page hashes.
            try run("/usr/bin/codesign", arguments: ["--force", "--sign", "-", library.path])
        }
        guard dlopen(library.path, RTLD_NOW | RTLD_LOCAL) != nil else {
            throw Failure(description: "could not load \(libraryName): \(dlerror().map { String(cString: $0) } ?? "")")
        }
        return library.path
    }

    private static func run(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(description: "\(([executablePath] + arguments).joined(separator: " ")) exited with \(process.terminationStatus): \(String(decoding: printed, as: UTF8.self))")
        }
    }
}
