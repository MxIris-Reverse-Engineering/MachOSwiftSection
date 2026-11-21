import Foundation
import MachOKit
import SwiftSectionFixtureSupport
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// A dynamic library compiled from source for one suite, rewritten after
/// linking when the suite asks, and loaded into the test process. Suites that
/// only read a compiled binary as a file call `FixtureCompiler` directly.
enum CompiledFixture {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Compiles `sources` — file names and their contents — into the arm64
    /// library `lib<name>.dylib` through the shared compiler, copies it to a
    /// directory of its own, hands the copied bytes to `rewrite` and signs the
    /// result again when there is one, and loads the copy. The compiled
    /// library is shared by every test, so it is never rewritten itself. The
    /// copy stays loaded after its directory is removed; the analyzers made
    /// from then on see it under the path this returns.
    @discardableResult
    static func load(
        named name: String,
        sources: KeyValuePairs<String, String>,
        compilerArguments: [String],
        rewrite: ((inout Data, MachOFile) throws -> Void)? = nil
    ) throws -> String {
        let compiledLibrary = try FixtureCompiler.shared.dynamicLibrary(
            named: name,
            language: .c,
            sourceFiles: sources.map { FixtureSourceFile(name: $0.key, contents: $0.value) },
            arguments: ["-arch", "arm64"] + compilerArguments
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrossReferenceAnalysisTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent(compiledLibrary.lastPathComponent)
        try FileManager.default.copyItem(at: compiledLibrary, to: library)
        if let rewrite {
            var bytes = try Data(contentsOf: library)
            try rewrite(&bytes, try MachOFile(url: library))
            try bytes.write(to: library)
            // Rewritten code no longer matches the signature's page hashes.
            try run("/usr/bin/codesign", arguments: ["--force", "--sign", "-", library.path])
        }
        guard dlopen(library.path, RTLD_NOW | RTLD_LOCAL) != nil else {
            throw Failure(description: "could not load \(library.lastPathComponent): \(dlerror().map { String(cString: $0) } ?? "")")
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
