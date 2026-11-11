import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for classes the Observation module's `@Observable`
/// macro expanded (evolution proposal `observable-macro-folding`), beside the
/// look-alikes the recognition must turn down: a class conforming to
/// `Observable` by hand, a stand-in for what SwiftData's `@Model` leaves (a
/// registrar of the same name and type beside `_$backingData`), and a
/// registrar field of another type.
///
/// One module, three variants:
/// - `.debug` (`-Onone`): every symbol, and the private backing storage's
///   accessors in the vtable.
/// - `.release` (`-O`): every symbol the optimizer leaves; the private
///   generated `shouldNotifyObservers(_:_:)` overloads of a final class are
///   gone.
/// - `.releaseStripped` (`-O`, then `strip -x`): as an OS framework or a
///   shipped app — an internal class keeps no symbol at all, a public one
///   only its exports, among them the initial-value expressions of its stored
///   properties.
package enum ObservableMacroFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case debug
        case release
        case releaseStripped
    }

    package static let moduleName = "ObservableMacroFixture"

    package static let swiftSource = """
    import Observation

    @propertyWrapper
    public struct Clamped {
        var storage: Int = 0
        public var wrappedValue: Int {
            get { storage }
            set { storage = min(newValue, 10) }
        }
        public init() {}
    }

    // Tracked properties with and without an initial value, and stored
    // properties the macro leaves alone: one whose name starts with an
    // underscore, a lazy one and a `let`.
    @Observable
    public final class FinalModel {
        public var name: String = ""
        var count: Int = 0
        var uninitialized: Double
        @ObservationIgnored var ignored: Double = 0
        @ObservationIgnored private var _cache: [Int] = []
        @ObservationIgnored lazy var lazyValue: Int = 1
        let constant: Int = 1
        public init() { uninitialized = 0 }
    }

    @Observable
    open class OpenModel {
        public var title: String = ""
        var items: [String] = []
        public init() {}
    }

    // Internal: a stripped image keeps no symbol of it.
    @Observable
    class InternalModel {
        var value: Int = 0
        var optionalText: String? = nil
        weak var delegate: AnyObject?
        @ObservationIgnored var _underscored: Int = 0
    }

    // Inherits the conformance: the macro generates no conformance record.
    @Observable
    class SubModel: OpenModel {
        var extra: Int = 0
    }

    @Observable
    final class GenericModel<Element> {
        var elements: [Element] = []
    }

    @Observable
    final class WrapperModel {
        @ObservationIgnored @Clamped var clamped: Int
        var tracked: Int = 0
        init() {}
    }

    final class ManualObservable: Observable {
        var plain: Int = 0
    }

    // What SwiftData's `@Model` leaves beside its registrar.
    final class PersistentModelStandIn {
        private var _$backingData: Int = 0
        private let _$observationRegistrar = ObservationRegistrar()
    }

    final class LookalikeRegistrar {
        private let _$observationRegistrar: Int = 0
    }
    """

    /// The classes `@Observable` expanded, by the name the source declares.
    package static let observableClassNames: Set<String> = [
        "FinalModel", "OpenModel", "InternalModel", "SubModel", "GenericModel", "WrapperModel",
    ]

    /// The classes and types the recognition must turn down.
    package static let lookalikeTypeNames: Set<String> = [
        "ManualObservable", "PersistentModelStandIn", "LookalikeRegistrar", "Clamped",
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

    /// Compiled once per process; every variant shares one working directory.
    private static let compilationResult: Result<[Variant: URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)

            var libraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                // Each variant its own install name: the in-process leg loads
                // one by path, and its image is told from the others by name.
                let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                let optimization = variant == .debug ? "-Onone" : "-O"
                try run(step: "swiftc (\(variant.rawValue))", [
                    // The language mode pinned: CI's toolchain and a newer
                    // local one must compile the same source the same way.
                    "swiftc", "-swift-version", "5", "-emit-library", optimization, "-module-name", moduleName,
                    "-Xlinker", "-install_name", "-Xlinker", libraryURL.path,
                    swiftSourceURL.path, "-o", libraryURL.path,
                ])
                if variant == .releaseStripped {
                    try run(step: "strip (\(variant.rawValue))", ["strip", "-x", libraryURL.path])
                }
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
        let libraryURL = try libraryURL(variant)
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The `.release` variant loaded into the test process — only that one:
    /// the variants define the same classes, and the Objective-C runtime keeps
    /// one of each.
    package static func loadedImage() throws -> MachOImage {
        let libraryURL = try libraryURL(.release)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}
