import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for telling a declaration a version cannot show from
/// one that is gone (evolution proposal `evolution-unobservable-presence`):
/// three versions of one module, the middle one stripped of its local symbols
/// (`strip -x`) — the shape of SwiftUI in the macOS 13.0–14.8 dyld shared
/// caches, between the symbol-rich 12.x and 15.0 builds.
///
/// The public surface is the same in every version except `retiredRender()`,
/// removed in 2.0: it is public, so the stripped version still names its
/// absence through the export trie and the removal is exact. The internal
/// members tell the other stories:
///
/// - `Panel.layout()` is in every version: invisible in 2.0, inferred present
///   there.
/// - `Panel.legacyLayout()` is in 1.0 and 2.0 and gone from 3.0: removed
///   somewhere between 1.0 and 3.0.
/// - `Panel.freshLayout()` arrives in 3.0: added somewhere between 1.0 and
///   3.0.
/// - `Int.panelScale()` is in every version, and its extension declares
///   nothing else, so in 2.0 the whole extension is invisible.
///
/// `Anchor` is `__DATA`-segment ballast: a module without a class compiles to
/// a dylib without one, a layout MachOKit releases before 0.52.103 mis-walked.
package enum UnobservablePresenceFixture {
    package static let moduleName = "UnobservablePresenceFixture"

    /// The version-axis labels, oldest first.
    package static let labels = ["1.0", "2.0", "3.0"]

    /// The index of the version stripped of its local symbols.
    package static let strippedVersionIndex = 1

    package static let sources: [String] = [
        // 1.0
        """
        public struct Panel {
            public var title: String

            public init(title: String) {
                self.title = title
            }

            public func render() -> Int {
                layout() + legacyLayout()
            }

            public func retiredRender() -> Int {
                0
            }

            func layout() -> Int {
                1
            }

            func legacyLayout() -> Int {
                2
            }
        }

        extension Int {
            func panelScale() -> Int {
                self * 2
            }
        }

        public class Anchor {
            public init() {}

            public func run() -> Int {
                Panel(title: "anchor").render() + 1.panelScale()
            }
        }
        """,
        // 2.0, stripped of its local symbols after linking
        """
        public struct Panel {
            public var title: String

            public init(title: String) {
                self.title = title
            }

            public func render() -> Int {
                layout() + legacyLayout()
            }

            func layout() -> Int {
                1
            }

            func legacyLayout() -> Int {
                2
            }
        }

        extension Int {
            func panelScale() -> Int {
                self * 2
            }
        }

        public class Anchor {
            public init() {}

            public func run() -> Int {
                Panel(title: "anchor").render() + 1.panelScale()
            }
        }
        """,
        // 3.0
        """
        public struct Panel {
            public var title: String

            public init(title: String) {
                self.title = title
            }

            public func render() -> Int {
                layout() + freshLayout()
            }

            func layout() -> Int {
                1
            }

            func freshLayout() -> Int {
                4
            }
        }

        extension Int {
            func panelScale() -> Int {
                self * 2
            }
        }

        public class Anchor {
            public init() {}

            public func run() -> Int {
                Panel(title: "anchor").render() + 1.panelScale()
            }
        }
        """,
    ]

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let step: String
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture \(step) failed:\n\(diagnostics)" }
    }

    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    /// Compiled once per process; the versions share one working directory.
    private static let compilationResult: Result<[URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            var libraryURLs: [URL] = []
            for (versionIndex, source) in sources.enumerated() {
                let versionName = "V\(versionIndex + 1)"
                let sourceURL = workingDirectory.appendingPathComponent("\(moduleName)\(versionName).swift")
                let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)\(versionName).dylib")
                try source.write(to: sourceURL, atomically: true, encoding: .utf8)
                // One module name across every version, so declarations key
                // identically; the language mode pinned, so CI's toolchain and
                // a newer local one compile the source the same way.
                try run(step: "swiftc (\(versionName))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", moduleName,
                    sourceURL.path, "-o", libraryURL.path,
                ])
                if versionIndex == strippedVersionIndex {
                    try run(step: "strip (\(versionName))", ["strip", "-x", libraryURL.path])
                }
                libraryURLs.append(libraryURL)
            }
            return libraryURLs
        }
    }()

    private static func run(step: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CompilationError(step: step, diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    /// The compiled versions, oldest first.
    package static func libraryURLs() throws -> [URL] {
        try compilationResult.get()
    }

    /// The compiled versions as readers, oldest first.
    package static func machOFiles() throws -> [MachOFile] {
        try libraryURLs().map { libraryURL in
            switch try MachOKit.loadFromFile(url: libraryURL) {
            case .machO(let machOFile):
                return machOFile
            case .fat(let fatFile):
                let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
                return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
            }
        }
    }
}
