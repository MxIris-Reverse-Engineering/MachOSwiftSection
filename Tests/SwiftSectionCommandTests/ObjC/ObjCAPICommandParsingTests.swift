import ArgumentParser
import Foundation
import Testing
@testable import swift_section

/// Option parsing for the API commands introduced by proposal 0006
/// (`snapshot` / `diff` / `evolution`). Same rationale as the dump/interface
/// parsing suite: the flag spelling is the CLI's contract, deliberately
/// aligned with `swift-section`'s commands of the same names.
@Suite("swift-section objc API command parsing")
struct ObjCAPICommandParsingTests {
    // MARK: - snapshot

    @Test("snapshot parses path, label, and output")
    func snapshotParsesEverything() throws {
        let command = try ObjCSnapshotCommand.parse([
            "/tmp/Sample", "--label", "26.0", "-o", "/tmp/baseline.json",
        ])
        #expect(command.machOOptions.filePath == "/tmp/Sample")
        #expect(command.label == "26.0")
        #expect(command.outputPath == "/tmp/baseline.json")
    }

    @Test("snapshot rejects the system cache flag")
    func snapshotRejectsSystemCache() {
        #expect(throws: (any Error).self) {
            try ObjCSnapshotCommand.parse(["--uses-system-dyld-shared-cache", "-n", "Foundation"])
        }
    }

    // MARK: - diff

    @Test("diff parses two positional paths and the report flags")
    func diffParsesPathsAndFlags() throws {
        let command = try ObjCDiffCommand.parse([
            "/tmp/old", "/tmp/new", "--json", "--fail-on-breaking", "-o", "/tmp/report.json",
        ])
        #expect(command.oldPath == "/tmp/old")
        #expect(command.newPath == "/tmp/new")
        #expect(command.json)
        #expect(command.failOnBreaking)
        #expect(command.outputPath == "/tmp/report.json")
        #expect(command.summaryOnly == false)
    }

    @Test("diff parses the shared-cache extraction options")
    func diffParsesCacheOptions() throws {
        let command = try ObjCDiffCommand.parse([
            "/tmp/cache-old", "/tmp/cache-new",
            "--dyld-shared-cache", "-n", "AppKit", "-a", "arm64e",
        ])
        #expect(command.isDyldSharedCache)
        #expect(command.cacheImageName == "AppKit")
        #expect(command.architecture == .arm64e)
    }

    @Test("diff rejects mutually exclusive report flags")
    func diffRejectsExclusiveFlags() {
        #expect(throws: (any Error).self) {
            try ObjCDiffCommand.parse(["/tmp/old", "/tmp/new", "--json", "--summary-only"])
        }
    }

    @Test("diff rejects cache image options without the cache flag")
    func diffRejectsImageOptionsWithoutCacheFlag() {
        #expect(throws: (any Error).self) {
            try ObjCDiffCommand.parse(["/tmp/old", "/tmp/new", "-n", "AppKit"])
        }
    }

    @Test("diff rejects the cache flag without an image selector")
    func diffRejectsCacheFlagWithoutImage() {
        #expect(throws: (any Error).self) {
            try ObjCDiffCommand.parse(["/tmp/old", "/tmp/new", "--dyld-shared-cache"])
        }
    }

    // MARK: - evolution

    @Test("evolution parses ordered inputs and labels")
    func evolutionParsesInputsAndLabels() throws {
        let command = try ObjCEvolutionCommand.parse([
            "/tmp/v1", "/tmp/v2", "/tmp/v3",
            "--labels", "17.0,18.0,26.0",
            "--summary-only",
        ])
        #expect(command.inputPaths == ["/tmp/v1", "/tmp/v2", "/tmp/v3"])
        #expect(command.labels == "17.0,18.0,26.0")
        #expect(command.summaryOnly)
    }

    @Test("evolution rejects fewer than two inputs")
    func evolutionRejectsSingleInput() {
        #expect(throws: (any Error).self) {
            try ObjCEvolutionCommand.parse(["/tmp/only-one"])
        }
    }

    @Test("evolution rejects mutually exclusive report flags")
    func evolutionRejectsExclusiveFlags() {
        #expect(throws: (any Error).self) {
            try ObjCEvolutionCommand.parse(["/tmp/v1", "/tmp/v2", "--json", "--summary-only"])
        }
    }
}
