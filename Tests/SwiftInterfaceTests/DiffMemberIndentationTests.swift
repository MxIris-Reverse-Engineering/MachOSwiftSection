import Foundation
import Testing
import MachOKit
import Semantic
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// The diff path's member-indentation contract, unified with the evolution
/// path: members render at printer level 0 — the accessor block's interior
/// indentation is RELATIVE to the declaration line — and the format layer
/// indents every line of a unit by the unit's level exactly once.
///
/// Before the unification the diff renderer rendered members at their real
/// level, so the printer-baked ABSOLUTE interior indentation ((level+1)*4 for
/// accessors, level*4 for the closing brace) stacked on top of the formatter's
/// per-line indent: a level-1 computed property's `get` sat at 12 interior
/// spaces instead of 8 and its closing brace at 8 instead of 4 — the sibling
/// of the evolution path's fixed accessor-block defect.
@Suite(.serialized)
struct DiffMemberIndentationTests {
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

    /// Two versions of one module, each carrying computed properties so every
    /// marker side of the member diff has a multi-line accessor block to pin:
    /// `summary` in both (unchanged, ` `), `legacySummary` only in the old
    /// version (removed, `-`), `freshSummary` only in the new (added, `+`).
    ///
    /// The `Anchor` class is load-bearing fixture ballast, not part of the
    /// scenario: a struct-only module compiles to a dylib with NO `__DATA`
    /// segment, and the pinned MachOKit release mis-walks that layout's
    /// chained-fixup pages during `resolveBind` — reading past the file
    /// mapping's end and crashing the indexer with SIGSEGV/SIGBUS. Any class
    /// forces a `__DATA` segment and keeps the fixture on the well-trodden
    /// layout (the evolution e2e fixture avoids the same landmine the same
    /// way, via its `Legacy` class).
    private static let fixtureSources: [String] = [
        """
        public struct Alpha {
            public var title: String
            public var summary: String { title }
            public var legacySummary: String { title }
        }
        public class Anchor {
            public func run() {}
        }
        """,
        """
        public struct Alpha {
            public var title: String
            public var summary: String { title }
            public var freshSummary: String { title }
        }
        public class Anchor {
            public func run() {}
        }
        """,
    ]

    // `Swift.Error` spelled out: the `Semantic` import brings its own `Error`
    // type into scope, which would otherwise win the lookup.
    private static let fixtureCompilationResult: Result<[URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DiffIndentFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            var libraryURLs: [URL] = []
            for (versionIndex, source) in fixtureSources.enumerated() {
                let sourceURL = workingDirectory.appendingPathComponent("DiffIndentFixtureV\(versionIndex + 1).swift")
                let libraryURL = workingDirectory.appendingPathComponent("libDiffIndentFixtureV\(versionIndex + 1).dylib")
                try source.write(to: sourceURL, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = [
                    "swiftc", "-emit-library", "-module-name", "DiffIndentFixture",
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
                    throw DiffIndentFixtureCompilationError(diagnostics: diagnostics)
                }
                libraryURLs.append(libraryURL)
            }
            return libraryURLs
        }
    }()

    private struct DiffIndentFixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "Diff-indentation fixture compilation failed:\n\(diagnostics)" }
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

    /// Every marker side renders its accessor block level-relative: after the
    /// 2-column marker+gutter prefix, the declaration line sits at the member
    /// level (4 spaces), the accessor one level deeper (8), and the closing
    /// brace back at the member level (4).
    @Test func accessorBlocksRenderLevelRelativeOnEveryMarkerSide() async throws {
        let machOFiles = try loadFixtureMachOFiles()
        let oldBuilder = SwiftDiffableInterfaceBuilder(in: machOFiles[0])
        try await oldBuilder.prepare()
        let newBuilder = SwiftDiffableInterfaceBuilder(in: machOFiles[1])
        try await newBuilder.prepare()

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let output = await renderer.printAnnotatedInterface().string

        #expect(
            output.contains("\n      var summary: Swift.String {\n          get\n      }"),
            "an unchanged accessor block must render level-relative; got:\n\(output)"
        )
        #expect(
            output.contains("\n-     var legacySummary: Swift.String {\n-         get\n-     }"),
            "a removed accessor block must render level-relative; got:\n\(output)"
        )
        #expect(
            output.contains("\n+     var freshSummary: Swift.String {\n+         get\n+     }"),
            "an added accessor block must render level-relative; got:\n\(output)"
        )
        // The double-indentation artifact: printer-baked absolute interior
        // indentation stacked on the formatter's per-line indent put 12
        // interior spaces before a level-1 member's `get`.
        #expect(
            !output.contains("            get"),
            "an accessor interior must never be indented twice; got:\n\(output)"
        )
    }
}
