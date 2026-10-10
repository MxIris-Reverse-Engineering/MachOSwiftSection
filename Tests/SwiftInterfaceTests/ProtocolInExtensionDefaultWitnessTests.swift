import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// A protocol declared in an extension of another module's type prints its
/// default-implementation extensions in the interface's top-level block for
/// nested protocols (evolution proposal `nested-definition-regions`). That
/// block reads the protocol's `defaultImplementationExtensions` before the
/// protocol itself is printed: it is printed — and indexed — inside the
/// extension declaring it, in the last block.
///
/// An extension the module indexer attaches during `prepare()` is there by
/// then; one the protocol's own index pass synthesizes is not. Under library
/// evolution a requirement whose default comes from a parent protocol's
/// extension — `Labeled.describe()`, from `extension Base` — is implemented by
/// a default witness named after the requirement itself, which no
/// protocol-extension block holds, so only the index pass finds it. That
/// extension printed nowhere: not after the protocol, which no longer trails
/// its extensions, and not in the top-level block, which ran first.
@Suite(.serialized)
struct ProtocolInExtensionDefaultWitnessTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "protocol-in-extension default-witness fixture compilation failed:\n\(diagnostics)" }
    }

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    private static let source = """
    public final class FixtureAnchor {}

    public protocol Base {}

    extension Base {
        public func describe() -> String { "base" }
    }

    extension Int {
        public protocol Labeled: Base {
            func describe() -> String
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProtocolInExtensionDefaultWitnessFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("ProtocolInExtensionDefaultWitness.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeDefaultWitness.dylib")
            // Library evolution makes `Labeled` resilient, which is what
            // gives its requirement a default witness of its own.
            try run(swiftcArguments: [
                "-swift-version", "5", "-O", "-emit-library", "-enable-library-evolution",
                "-module-name", "ProbeDefaultWitness",
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ])
            return libraryURL
        }
    }()

    private static func run(swiftcArguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc"] + swiftcArguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain before waiting, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    private func makeBuilder() async throws -> SwiftInterfaceBuilder<MachOFile> {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return builder
    }

    @Test("a default implementation only the protocol's own index finds prints in the interface")
    func defaultImplementationFoundByTheIndexPassPrints() async throws {
        let interface = try await makeBuilder().printRoot().string

        let topLevelExtensionLines = interface.split(separator: "\n").filter { $0.hasPrefix("extension ") }
        #expect(topLevelExtensionLines.contains { $0.contains("Int.Labeled") }, "\(interface)")
    }

    @Test("printing the same builder twice gives the same interface")
    func printingTwiceGivesTheSameInterface() async throws {
        let builder = try await makeBuilder()

        let firstInterface = try await builder.printRoot().string
        let secondInterface = try await builder.printRoot().string

        #expect(firstInterface == secondInterface)
    }
}
