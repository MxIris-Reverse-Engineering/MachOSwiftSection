import Foundation
import MachOKit
import Testing

/// An on-the-fly fixture for members whose implementation symbol the
/// optimizer deleted while another entry point of theirs survived (evolution
/// proposal `thunk-only-objc-members`), compiled twice from one source:
/// - `.unoptimized` (`-Onone`): every entry point keeps its symbol — the
///   independent truth of what the classes declare.
/// - `.wholeModuleOptimized` (`-O -wmo`): the shape of an app's release
///   build. Whole-module optimization lets the optimizer see every use of an
///   internal member, so once those uses are inlined it deletes the entry
///   point. The small `@objc` members are inlined into their Objective-C
///   thunks, which leaves each thunk (`$s…To`) as the member's only symbol;
///   the allocating entry point of `InitializingEntryOnlyHolder.init(values:)`
///   is inlined into both of its callers, while the initializing entry point
///   is too large to inline and stays (`…fc` without `…fC`); so do
///   `ThunkOnlyWidget.init(tags:)`'s, a Swift-only initializer beside the
///   class's `@objc` `init()`; and the synthesized `init()` of the generic
///   class keeps only its initializing entry point and its thunk.
///
/// Xcode 27.2's `Xcode Service` executable has the same shapes in the wild:
/// `MenuBarPanelWindow.canBecomeKey` and `XcodeServiceAppDelegate`'s
/// `NSApplicationDelegate` methods as thunks alone, nine class initializers
/// as initializing entry points alone.
package enum ThunkOnlyMemberFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case unoptimized
        case wholeModuleOptimized
    }

    package static let moduleName = "ThunkOnlyMemberFixture"

    package static let source = """
    import Foundation

    // Internal on purpose: only an internal member's every use is visible to
    // whole-module optimization, so only its entry points can be deleted.
    class ThunkOnlyWidget: NSObject {
        let normalizedTagCount: Int

        override var description: String { "ThunkOnlyWidget" }
        override func isEqual(_ object: Any?) -> Bool { object is ThunkOnlyWidget }
        @objc func handleTick(_ sender: Any?) {}
        @objc class func classTick() -> Int { 1 }
        override init() {
            normalizedTagCount = 0
            super.init()
        }

        // Swift-only beside the `@objc` `init()`: it has no thunk of its own.
        init(tags: [String]) {
            var normalizedTags: [String] = []
            for tag in tags {
                normalizedTags.append(tag.trimmingCharacters(in: .whitespaces).lowercased())
            }
            normalizedTagCount = Set(normalizedTags).count
            super.init()
        }
    }

    // Declared in the class's own module, so filed as a member of the class.
    extension ThunkOnlyWidget {
        @objc func handleExtensionTick(_ sender: Any?) {}
    }

    // Another module's class: filed as an extension member.
    extension NSObject {
        @objc func thunkOnlyFixtureHook() {}
    }

    // A generic class has no static class object, so there is no ObjC method
    // table to tie these members to.
    class GenericThunkOnlyWidget<Element>: NSObject {
        override var description: String { "GenericThunkOnlyWidget" }
        @objc func handleTick(_ sender: Any?) {}
    }

    class InitializingEntryOnlyHolder {
        var values: [String]
        var total: Int
        var lookup: [String: Int]

        init(values: [String]) {
            var lookup: [String: Int] = [:]
            var total = 0
            for (index, value) in values.enumerated() {
                let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
                lookup[normalized, default: 0] += index
                total += normalized.count * (index + 1)
            }
            self.values = values.sorted()
            self.total = total
            self.lookup = lookup
        }
    }

    public func makeFixtureObjects() -> [AnyObject] {
        [ThunkOnlyWidget(), ThunkOnlyWidget(tags: ["a", " B "]), GenericThunkOnlyWidget<Int>(), InitializingEntryOnlyHolder(values: ["a", " B "])]
    }

    public func makeMoreFixtureObjects() -> [AnyObject] {
        [ThunkOnlyWidget(tags: ["c"]), InitializingEntryOnlyHolder(values: ["c"])]
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let step: String
        package let diagnostics: String
        package var description: String { "\(ThunkOnlyMemberFixture.moduleName) fixture \(step) failed:\n\(diagnostics)" }
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

    /// Compiled once per process; both variants share one working directory.
    private static let compilationResult: Result<[Variant: URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            var libraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                let optimizationArguments = switch variant {
                case .unoptimized: ["-Onone"]
                case .wholeModuleOptimized: ["-O", "-wmo"]
                }
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                try run(step: "swiftc (\(variant.rawValue))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-module-name", moduleName,
                ] + optimizationArguments + [
                    sourceURL.path, "-framework", "Foundation", "-o", libraryURL.path,
                ])
                libraries[variant] = libraryURL
            }
            return libraries
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

    package static func libraryURL(_ variant: Variant) throws -> URL {
        let libraries = try compilationResult.get()
        guard let libraryURL = libraries[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no library for variant \(variant.rawValue)")
        }
        return libraryURL
    }

    package static func machOFile(_ variant: Variant) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: try libraryURL(variant)) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The `.wholeModuleOptimized` build loaded into the test process — only
    /// that one: both builds define the same Objective-C classes.
    package static func loadedOptimizedImage() throws -> MachOImage {
        let libraryURL = try libraryURL(.wholeModuleOptimized)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the optimized fixture dylib did not load in-process")
    }
}
