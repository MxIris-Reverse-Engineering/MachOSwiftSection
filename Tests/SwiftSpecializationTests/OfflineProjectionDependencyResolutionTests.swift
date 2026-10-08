@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
import MachOTestingSupport
import SwiftDeclarationRendering

/// An archived iOS simulator cache: the dependency closure an iOS simulator
/// binary is printed against here. Machine-specific, hence the suite's
/// condition.
private let iOSSimulatorCachePath = "/Volumes/DyldSharedCaches/iOS-Simulator/27.0/dyld_sim_shared_cache_arm64"

/// A field of an offline specialization (evolution proposal
/// `offline-generic-specialization`) names a member of a concrete type by the
/// type its witness record names — `[Swift.Int].Element` reads `Swift.Int` —
/// and the layout comments beside it are computed over the dependency closure
/// the print configuration names (`staticLayoutDependencyResolution`). The
/// projection built a closure of its own, from the thunk resolver's search
/// paths or the ones inferred from the file's location plus the running
/// system's cache, so the field's name and its layout were read from two
/// different sets of images. An iOS binary stored outside any runtime tree and
/// printed against an iOS cache has its layout computed and its field left
/// as `[Swift.Int].Element?`: the host's macOS images are never candidates for
/// an iOS root.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: iOSSimulatorCachePath)))
struct OfflineProjectionDependencyResolutionTests {
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
        var description: String { "iOS simulator projection fixture compilation failed:\n\(diagnostics)" }
    }

    private static let moduleName = "SimulatorProjectionFixture"

    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public struct ElementsHolder<Elements: Collection> {
        public var elements: Elements
        public var first: Elements.Element?
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("\(moduleName).swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "--sdk", "iphonesimulator",
                "swiftc", "-swift-version", "5", "-emit-library", "-module-name", moduleName,
                "-target", "arm64-apple-ios17.0-simulator",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain before waiting, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    @Test("a field's projected member and its layout are read from the same images")
    func projectedMemberAndLayoutAreReadFromTheSameImages() async throws {
        let machOFile = try loadFixtureMachOFile()
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        let definition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == "ElementsHolder" })
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype([Int].self)])
        let specialized = try await definition.specialize(with: result, in: machOFile)
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printTypeLayout = true
        configuration.staticLayoutDependencyResolution = .dependencyClosure(searchPaths: [.dyldSharedCache(path: iOSSimulatorCachePath)])
        let printer = SwiftDeclarationPrinter<MachOFile>(configuration: configuration, in: machOFile)

        let printed = try await printer.printTypeDefinition(specialized).string

        let firstFieldLine = try #require(printed.split(separator: "\n").first { $0.contains("var first:") }, "\(printed)")
        #expect(firstFieldLine.contains("Swift.Int") && !firstFieldLine.contains("Element"), "\(printed)")
    }
}
