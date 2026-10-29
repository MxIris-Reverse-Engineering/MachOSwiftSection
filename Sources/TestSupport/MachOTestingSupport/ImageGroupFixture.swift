import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for an evolution whose versions are groups of
/// images (evolution proposal `image-group-evolution`): one module split
/// across two images from 2.0 on, the way SwiftUI split into SwiftUI and
/// SwiftUICore in macOS 15.
///
/// 1.0 is the module alone, `ImageGroupFixture`. From 2.0 on a second image,
/// `ImageGroupFixtureCore`, defines `Gauge` under
/// `@_originallyDefinedIn(module: "ImageGroupFixture", …)`, so its mangled
/// name — and every member's — keeps the module name it had in 1.0. The
/// stories the versions tell:
///
/// - `Gauge` moves into the core image in 2.0; `reading()`, `value` and
///   `init(value:)` move with it.
/// - `Gauge.calibrated()` stays in `ImageGroupFixture` in 2.0, declared in an
///   extension of a type that now lives in another image — mangled with no
///   extension context, as SwiftUI declares members of SwiftUICore's types —
///   and moves into the core image's `Gauge` in 3.0.
/// - `Gauge.standard` stays in `ImageGroupFixture` throughout.
/// - `Needle` arrives in the core image in 2.0; `ImageGroupFixture` extends
///   it from 2.0 on with `sweep()`, an ordinary cross-module extension whose
///   mangling names the extension.
/// - `Dial` stays in `ImageGroupFixture` and never changes.
package enum ImageGroupFixture {
    /// The module every version declares, and the image it lives in.
    package static let moduleName = "ImageGroupFixture"

    /// The module, and image, the split moves declarations into from 2.0 on.
    package static let coreModuleName = "ImageGroupFixtureCore"

    /// The version-axis labels, oldest first.
    package static let labels = ["1.0", "2.0", "3.0"]

    /// One image of a version: its name and its reader.
    package struct Image {
        package let name: String
        package let machOFile: MachOFile
    }

    /// Per version, oldest first: the core image's source (`nil` before the
    /// split) and the module's.
    package static let sources: [(core: String?, module: String)] = [
        // 1.0
        (
            core: nil,
            module: """
            public struct Gauge {
                public var value: Int

                public init(value: Int) {
                    self.value = value
                }

                public func reading() -> Int {
                    value
                }

                public func calibrated() -> Int {
                    value + 1
                }

                public static var standard: Gauge {
                    Gauge(value: 0)
                }
            }

            public struct Dial {
                public init() {}

                public func turn() -> Int {
                    1
                }
            }
            """
        ),
        // 2.0
        (
            core: """
            @_originallyDefinedIn(module: "ImageGroupFixture", macOS 14.0)
            @available(macOS 10.15, *)
            public struct Gauge {
                public var value: Int

                public init(value: Int) {
                    self.value = value
                }

                public func reading() -> Int {
                    value
                }
            }

            public struct Needle {
                public init() {}
            }
            """,
            module: """
            @_exported import ImageGroupFixtureCore

            @available(macOS 10.15, *)
            extension Gauge {
                public func calibrated() -> Int {
                    value + 1
                }

                public static var standard: Gauge {
                    Gauge(value: 0)
                }
            }

            extension Needle {
                public func sweep() -> Int {
                    2
                }
            }

            public struct Dial {
                public init() {}

                public func turn() -> Int {
                    1
                }
            }
            """
        ),
        // 3.0
        (
            core: """
            @_originallyDefinedIn(module: "ImageGroupFixture", macOS 14.0)
            @available(macOS 10.15, *)
            public struct Gauge {
                public var value: Int

                public init(value: Int) {
                    self.value = value
                }

                public func reading() -> Int {
                    value
                }

                public func calibrated() -> Int {
                    value + 1
                }
            }

            public struct Needle {
                public init() {}
            }
            """,
            module: """
            @_exported import ImageGroupFixtureCore

            @available(macOS 10.15, *)
            extension Gauge {
                public static var standard: Gauge {
                    Gauge(value: 0)
                }
            }

            extension Needle {
                public func sweep() -> Int {
                    2
                }
            }

            public struct Dial {
                public init() {}

                public func turn() -> Int {
                    1
                }
            }
            """
        ),
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

    /// The deployment target every image is built for: one
    /// `@_originallyDefinedIn` can name, and any host running the tests has.
    private static let target = "arm64-apple-macos14.0"

    /// Compiled once per process, each version in a directory of its own,
    /// since every version reuses the two module names. Per version the
    /// libraries' URLs, the core image's first when there is one.
    private static let compilationResult: Result<[[(name: String, libraryURL: URL)]], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            var librariesPerVersion: [[(name: String, libraryURL: URL)]] = []
            for (versionIndex, versionSources) in sources.enumerated() {
                let versionName = "V\(versionIndex + 1)"
                let versionDirectory = workingDirectory.appendingPathComponent(versionName)
                try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
                var libraries: [(name: String, libraryURL: URL)] = []
                var linkArguments: [String] = []
                if let coreSource = versionSources.core {
                    let coreSourceURL = versionDirectory.appendingPathComponent("\(coreModuleName).swift")
                    let coreLibraryURL = versionDirectory.appendingPathComponent("lib\(coreModuleName).dylib")
                    try coreSource.write(to: coreSourceURL, atomically: true, encoding: .utf8)
                    // The language mode pinned, so CI's toolchain and a newer
                    // local one compile the source the same way.
                    try run(step: "swiftc \(coreModuleName) (\(versionName))", [
                        "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-target", target,
                        "-module-name", coreModuleName,
                        "-emit-module", "-emit-module-path", versionDirectory.appendingPathComponent("\(coreModuleName).swiftmodule").path,
                        coreSourceURL.path, "-o", coreLibraryURL.path,
                    ])
                    libraries.append((coreModuleName, coreLibraryURL))
                    linkArguments = ["-I", versionDirectory.path, "-L", versionDirectory.path, "-l\(coreModuleName)"]
                }
                let moduleSourceURL = versionDirectory.appendingPathComponent("\(moduleName).swift")
                let moduleLibraryURL = versionDirectory.appendingPathComponent("lib\(moduleName).dylib")
                try versionSources.module.write(to: moduleSourceURL, atomically: true, encoding: .utf8)
                try run(step: "swiftc \(moduleName) (\(versionName))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-target", target,
                    "-module-name", moduleName,
                ] + linkArguments + [
                    moduleSourceURL.path, "-o", moduleLibraryURL.path,
                ])
                libraries.insert((moduleName, moduleLibraryURL), at: 0)
                librariesPerVersion.append(libraries)
            }
            return librariesPerVersion
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

    /// Each version's images, oldest version first; within a version the
    /// module's own image first, then the core image when there is one.
    package static func imageGroups() throws -> [[Image]] {
        try compilationResult.get().map { libraries in
            try libraries.map { library in
                try Image(name: library.name, machOFile: machOFile(at: library.libraryURL))
            }
        }
    }

    /// The image named `imageName` in the version at `versionIndex`.
    package static func image(named imageName: String, atVersion versionIndex: Int) throws -> MachOFile {
        let image = try imageGroups()[versionIndex].first { $0.name == imageName }
        return try #require(image, "\(imageName) is not part of version \(labels[versionIndex])").machOFile
    }

    private static func machOFile(at libraryURL: URL) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }
}
