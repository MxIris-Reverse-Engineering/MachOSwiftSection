import Foundation
import Testing
import MachOKit
import Semantic
import SwiftDiffing
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// End-to-end tests for the annotated evolution interface over three
/// on-the-fly-compiled versions of one fixture module (the
/// `LegacyDyldInfoBindTests` compilation approach, minus the legacy target):
///
/// - v1 → v2: `Alpha.bar(id:)` added, `Legacy` (whole class) removed.
/// - v2 → v3: `Alpha.bar()` removed, `Alpha.count` changes `Int32 → Int64`,
///   enum case `east` added.
///
/// Asserted: the legend, each lifecycle annotation (bitmap + phrase), the
/// bareness of never-changed declarations, the union ordering rule (newest
/// spine, removed declarations appended), and the structured stream's axis
/// alignment.
@Suite(.serialized)
struct SwiftEvolutionInterfaceBuilderTests {
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

    private static let fixtureSources: [String] = [
        // v1
        """
        public struct Alpha {
            public var title: String
            public var count: Int32
            public func bar() -> Int { 1 }
        }
        public class Legacy {
            public func run() {}
        }
        public enum Direction {
            case north
            case south
        }
        """,
        // v2
        """
        public struct Alpha {
            public var title: String
            public var count: Int32
            public func bar() -> Int { 1 }
            public func bar(id: Int) -> Int { id }
        }
        public enum Direction {
            case north
            case south
        }
        """,
        // v3
        """
        public struct Alpha {
            public var title: String
            public var count: Int64
            public func bar(id: Int) -> Int { id }
        }
        public enum Direction {
            case north
            case south
            case east
        }
        """,
    ]

    // `Swift.Error` spelled out: the `Semantic` import brings its own `Error`
    // type into scope, which would otherwise win the lookup.
    private static let fixtureCompilationResult: Result<[URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EvolutionInterfaceFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            var libraryURLs: [URL] = []
            for (versionIndex, source) in fixtureSources.enumerated() {
                let sourceURL = workingDirectory.appendingPathComponent("EvolutionFixtureV\(versionIndex + 1).swift")
                let libraryURL = workingDirectory.appendingPathComponent("libEvolutionFixtureV\(versionIndex + 1).dylib")
                try source.write(to: sourceURL, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                // One module name across every version — the axis tracks the
                // same module, so declarations key identically.
                process.arguments = [
                    "swiftc", "-emit-library", "-module-name", "EvolutionFixture",
                    sourceURL.path, "-o", libraryURL.path,
                ]
                let standardErrorPipe = Pipe()
                process.standardError = standardErrorPipe
                try process.run()
                // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
                let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let diagnostics = String(decoding: diagnosticsData, as: UTF8.self)
                    throw EvolutionFixtureCompilationError(diagnostics: diagnostics)
                }
                libraryURLs.append(libraryURL)
            }
            return libraryURLs
        }
    }()

    private struct EvolutionFixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "Evolution fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFiles() throws -> [MachOFile] {
        try Self.fixtureCompilationResult.get().map { libraryURL in
            let file = try MachOKit.loadFromFile(url: libraryURL)
            switch file {
            case .machO(let machOFile):
                return machOFile
            case .fat(let fatFile):
                let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
                return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
            }
        }
    }

    private func preparedBuilder() async throws -> SwiftEvolutionInterfaceBuilder {
        let builder = try SwiftEvolutionInterfaceBuilder(
            versions: try loadFixtureMachOFiles(),
            labels: ["1.0", "2.0", "3.0"]
        )
        try await builder.prepare()
        return builder
    }

    // MARK: - The annotated interface

    @Test func annotatedInterfaceCarriesEveryLifecycleAnnotation() async throws {
        let builder = try await preparedBuilder()
        let interface = try await builder.printAnnotatedInterface().string
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func line(containing needles: String...) throws -> String {
            try #require(
                lines.first { line in needles.allSatisfy(line.contains) },
                "no line containing \(needles) in:\n\(interface)"
            )
        }

        // Legend.
        #expect(interface.hasPrefix("""
        // Swift ABI evolution across 3 versions: 1.0 → 2.0 → 3.0
        // Bitmap positions: [1] 1.0  [2] 2.0  [3] 3.0
        """))

        // Removed member: renders from its last-carrying version, annotated.
        let removedFunction = try line(containing: "func bar()", "->")
        #expect(removedFunction.contains("// [●●○] removed in 3.0"))

        // Added member.
        let addedFunction = try line(containing: "func bar(id:")
        #expect(addedFunction.contains("// [○●●] added in 2.0"))

        // Modified field: single line (newest generation), old shape in the phrase.
        let modifiedField = try line(containing: "modified in 3.0")
        #expect(modifiedField.contains("Swift.Int32"))
        #expect(modifiedField.contains("Swift.Int64"))
        #expect(modifiedField.contains("→"))

        // Removed container: header annotated, body rendered from v1.
        let removedClass = try line(containing: "Legacy", "{")
        #expect(removedClass.contains("// [●○○] removed in 2.0"))
        #expect(try line(containing: "func run()").isEmpty == false)

        // Added enum case.
        let addedCase = try line(containing: "case east")
        #expect(addedCase.contains("// [○○●] added in 3.0"))

        // Never-changed declarations carry no annotation.
        #expect(try !line(containing: "var title").contains("// ["))
        #expect(try !line(containing: "case north").contains("// ["))
    }

    /// Union ordering: the newest version's declaration order is the spine;
    /// a declaration absent from the newest version (the removed `Legacy`
    /// class) is appended after the spine's declarations.
    @Test func removedDeclarationsAppendAfterTheNewestSpine() async throws {
        let builder = try await preparedBuilder()
        let interface = try await builder.printAnnotatedInterface().string
        let alphaPosition = try #require(interface.range(of: "Alpha"))
        let legacyPosition = try #require(interface.range(of: "Legacy"))
        let directionPosition = try #require(interface.range(of: "Direction"))
        #expect(alphaPosition.lowerBound < legacyPosition.lowerBound)
        #expect(directionPosition.lowerBound < legacyPosition.lowerBound)
    }

    // MARK: - Structured stream & evolution reuse

    @Test func structuredStreamAlignsWithTheVersionAxis() async throws {
        let builder = try await preparedBuilder()
        let blocks = try await builder.annotatedBlocks()
        #expect(!blocks.isEmpty)
        var annotatedLineCount = 0
        for block in blocks {
            for line in block {
                guard let annotation = line.annotation else { continue }
                annotatedLineCount += 1
                #expect(annotation.presence.count == 3)
                #expect(!annotation.events.isEmpty)
            }
        }
        #expect(annotatedLineCount > 0)
    }

    @Test func evolutionIsExposedForVerdictReuse() async throws {
        let builder = try await preparedBuilder()
        let evolution = try #require(builder.evolution)
        // Removals on the axis make it ABI-breaking — the CI gate's input.
        #expect(evolution.hasBreakingChange)
        #expect(evolution.versions.map(\.label) == ["1.0", "2.0", "3.0"])
    }

    // MARK: - Contracts

    @Test func renderingBeforePrepareThrowsNotPrepared() async throws {
        let builder = try SwiftEvolutionInterfaceBuilder(
            versions: try loadFixtureMachOFiles(),
            labels: ["1.0", "2.0", "3.0"]
        )
        await #expect(throws: SwiftEvolutionInterfaceBuilderError.notPrepared) {
            _ = try await builder.printAnnotatedInterface()
        }
    }

    @Test func initializerRejectsInvalidInputShapes() throws {
        let machOFiles = try loadFixtureMachOFiles()
        #expect(throws: ABIEvolutionError.fewerThanTwoVersions(versionCount: 1)) {
            _ = try SwiftEvolutionInterfaceBuilder(versions: [machOFiles[0]], labels: ["1.0"])
        }
        #expect(throws: ABIEvolutionError.labelCountMismatch(labelCount: 2, versionCount: 3)) {
            _ = try SwiftEvolutionInterfaceBuilder(versions: machOFiles, labels: ["1.0", "2.0"])
        }
    }

    /// For N == 2 the annotations must tell exactly the two-sided differ's
    /// story (the evolution builder pins event equality upstream; this pins
    /// the interface view of it).
    @Test func twoVersionAxisMatchesTheTwoSidedDiffStory() async throws {
        let machOFiles = try loadFixtureMachOFiles()
        let builder = try SwiftEvolutionInterfaceBuilder(
            versions: [machOFiles[1], machOFiles[2]],
            labels: ["2.0", "3.0"]
        )
        try await builder.prepare()
        let interface = try await builder.printAnnotatedInterface().string
        #expect(interface.contains("// [●○] removed in 3.0"))
        #expect(interface.contains("// [○●] added in 3.0"))
        #expect(!interface.contains("[●●○]"))
    }
}
