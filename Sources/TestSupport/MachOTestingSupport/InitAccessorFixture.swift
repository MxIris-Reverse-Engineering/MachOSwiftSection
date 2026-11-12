import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for SE-0400 init accessors (evolution proposal
/// `init-accessor-recovery`): computed properties whose init accessor
/// initializes a stored property named after them, one named otherwise, two
/// at once, or only accesses one; SwiftUICore's two shapes — a frozen struct
/// whose `@usableFromInline` init accessor is exported, and a stored property
/// with a function under its init accessor's name, kept for the clients that
/// inlined a call to it — and SwiftData's, a `_name` of another type.
///
/// One module, built with library evolution as SwiftUICore is, in four
/// variants:
/// - `.debug` (`-Onone`): every init accessor, each called by its
///   initializer.
/// - `.release` (`-O`): every init accessor, as local symbols: the
///   initializers inlined them, but nothing removes them.
/// - `.releaseDeadStripped` (`-O`, linked with `-dead_strip`): as SwiftUI —
///   the local symbols kept, but every function nothing references dropped,
///   which is every init accessor the image does not export.
/// - `.releaseStripped` (`-O`, then `strip -x`): as an OS framework or a
///   shipped app — only the exported init accessors.
package enum InitAccessorFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case debug
        case release
        case releaseDeadStripped
        case releaseStripped
    }

    package static let moduleName = "InitAccessorFixture"

    package static let swiftSource = """
    // Initializes a stored property named otherwise: nothing in the image
    // tells which.
    public struct Angle {
        public var degrees: Double
        public var radians: Double {
            @storageRestrictions(initializes: degrees)
            init(initialValue) { degrees = initialValue * 180 / .pi }
            get { degrees * .pi / 180 }
            set { degrees = newValue * 180 / .pi }
        }
        public init(radians: Double) { self.radians = radians }
    }

    // Accesses a stored property, and initializes none.
    public struct Titled {
        private var dictionary: [String: String]
        public var title: String {
            @storageRestrictions(accesses: dictionary)
            init(newValue) { dictionary["title"] = newValue }
            get { dictionary["title"] ?? "" }
            set { dictionary["title"] = newValue }
        }
        public init(title: String) {
            dictionary = [:]
            self.title = title
        }
    }

    // Initializes two stored properties at once.
    public struct Pair {
        private var _x: Int
        private var _y: Int
        public var point: (x: Int, y: Int) {
            @storageRestrictions(initializes: _x, _y)
            init(initialValue) { (_x, _y) = initialValue }
            get { (_x, _y) }
            set { (_x, _y) = newValue }
        }
        public init(point: (x: Int, y: Int)) { self.point = point }
    }

    // Both lists, and the default parameter name.
    public struct Mixed {
        private var _a: String
        private var b: Int
        public var a: String {
            @storageRestrictions(initializes: _a, accesses: b)
            init { _a = newValue + String(b) }
            get { _a }
            set { _a = newValue }
        }
        public init(a: String, b: Int) {
            self.b = b
            self.a = a
        }
    }

    // SwiftUICore's `_GeometryActionModifier2.value`: an inlinable
    // initializer a client may inline calls the init accessor, so it is
    // exported.
    @frozen
    public struct FrozenBox<Value> {
        @usableFromInline var _value: Value
        public var value: Value {
            @usableFromInline
            @storageRestrictions(initializes: _value)
            init(initialValue) { _value = initialValue }
            get { _value }
            set { _value = newValue }
        }
        @inlinable public init(value: Value) { self.value = value }
    }

    // SwiftUICore's `_GeometryActionModifier2.value` again: the getter and
    // setter keep the mangling from before the type became `@Sendable`, so
    // only the init accessor spells the property's type as its field has it.
    public struct SendableUpgrade {
        private var _value: @Sendable (Int) -> Int
        public var value: @Sendable (Int) -> Int {
            @storageRestrictions(initializes: _value)
            init(initialValue) { _value = initialValue }
            @_silgen_name("$s19InitAccessorFixture15SendableUpgradeV5valueyS2icvg")
            get { _value }
            @_silgen_name("$s19InitAccessorFixture15SendableUpgradeV5valueyS2icvs")
            set { _value = newValue }
        }
        public init(value: @escaping @Sendable (Int) -> Int) { self.value = value }
    }

    // A class, and a storage whose field type is `weak Swift.AnyObject?`.
    public final class Model {
        private var _name: String
        private weak var _delegate: AnyObject?
        public var name: String {
            @storageRestrictions(initializes: _name)
            init(initialValue) { _name = initialValue }
            get { _name }
            set { _name = newValue }
        }
        public var delegate: AnyObject? {
            @storageRestrictions(initializes: _delegate)
            init(initialValue) { _delegate = initialValue }
            get { _delegate }
            set { _delegate = newValue }
        }
        public init(name: String, delegate: AnyObject?) {
            self.name = name
            self.delegate = delegate
        }
    }

    // SwiftData's `@Model` shape: `_name` holds a placeholder of another
    // type, and the value lives in the storage the accessor accesses.
    public struct Placeholder {
        public init() {}
    }

    public struct PersistedLookalike {
        private var _name: Placeholder
        private var storage: [String: String]
        public var name: String {
            @storageRestrictions(initializes: _name, accesses: storage)
            init(initialValue) {
                storage["name"] = initialValue
                _name = Placeholder()
            }
            get { storage["name"] ?? "" }
            set { storage["name"] = newValue }
        }
        public init(name: String) {
            storage = [:]
            self.name = name
        }
    }

    // SwiftUICore's `_GeometryActionModifier.value`: computed with an init
    // accessor once, stored now, and a function keeps the init accessor's
    // symbol for the clients that inlined a call to it.
    @frozen
    public struct ShimmedBox {
        public var value: Int
        @_silgen_name("$s19InitAccessorFixture10ShimmedBoxV5valueSivi")
        @usableFromInline
        internal mutating func valueInitAccessorABIShim(value: Int) {
            self.value = value
        }
        @inlinable public init(value: Int) { self.value = value }
    }
    """

    /// A computed property with an init accessor, by its type's and its own
    /// name.
    package struct Property: Hashable, Sendable, CustomStringConvertible {
        package let typeName: String
        package let name: String

        package init(_ typeName: String, _ name: String) {
            self.typeName = typeName
            self.name = name
        }

        package var description: String { "\(typeName).\(name)" }
    }

    /// Every computed property the source gives an init accessor.
    package static let propertiesWithInitAccessors: [Property] = [
        Property("Angle", "radians"),
        Property("Titled", "title"),
        Property("Pair", "point"),
        Property("Mixed", "a"),
        Property("FrozenBox", "value"),
        Property("SendableUpgrade", "value"),
        Property("Model", "name"),
        Property("Model", "delegate"),
        Property("PersistedLookalike", "name"),
    ]

    /// The init accessors the image exports, which every variant keeps.
    package static let propertiesWithExportedInitAccessors: Set<Property> = [
        Property("FrozenBox", "value"),
    ]

    /// What `@storageRestrictions(initializes:)` is inferred to list: a
    /// stored property named `_<name>` with the property's type — the type
    /// the init accessor names, which `SendableUpgrade.value`'s getter does
    /// not. `Mixed.a` also accesses `b`, which nothing infers.
    package static let inferredInitializedFieldNames: [Property: [String]] = [
        Property("Mixed", "a"): ["_a"],
        Property("FrozenBox", "value"): ["_value"],
        Property("SendableUpgrade", "value"): ["_value"],
        Property("Model", "name"): ["_name"],
        Property("Model", "delegate"): ["_delegate"],
    ]

    /// The stored property a function keeps an init accessor's symbol for.
    package static let storedPropertyWithInitAccessorSymbol = Property("ShimmedBox", "value")

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

    /// Compiled once per process, on a thread of its own, as
    /// `ObservableMacroFixture` is: a test that needs the fixture suspends
    /// until it is built instead of holding a cooperative thread through
    /// four compiles.
    private static let compilation = OneTimeCompilation()

    private final class OneTimeCompilation: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<[Variant: URL], Swift.Error>?
        private var waiters: [CheckedContinuation<[Variant: URL], Swift.Error>] = []
        private var hasStarted = false

        func libraries() async throws -> [Variant: URL] {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                waiters.append(continuation)
                let startsCompilation = !hasStarted
                hasStarted = true
                lock.unlock()
                guard startsCompilation else { return }
                Thread {
                    let result = Result { try InitAccessorFixture.compileLibraries() }
                    self.lock.lock()
                    self.result = result
                    let waiters = self.waiters
                    self.waiters = []
                    self.lock.unlock()
                    for waiter in waiters {
                        waiter.resume(with: result)
                    }
                }.start()
            }
        }
    }

    /// Every variant, in one working directory.
    private static func compileLibraries() throws -> [Variant: URL] {
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
            let deadStripping = variant == .releaseDeadStripped ? ["-Xlinker", "-dead_strip"] : []
            try run(step: "swiftc (\(variant.rawValue))", [
                // The language mode pinned: CI's toolchain and a newer
                // local one must compile the same source the same way.
                "swiftc", "-swift-version", "5", "-enable-library-evolution", "-emit-library", optimization, "-module-name", moduleName,
                "-Xlinker", "-install_name", "-Xlinker", libraryURL.path,
            ] + deadStripping + [
                swiftSourceURL.path, "-o", libraryURL.path,
            ])
            if variant == .releaseStripped {
                try run(step: "strip (\(variant.rawValue))", ["strip", "-x", libraryURL.path])
            }
            libraries[variant] = libraryURL
        }
        return libraries
    }

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

    package static func libraryURL(_ variant: Variant) async throws -> URL {
        let libraries = try await compilation.libraries()
        guard let libraryURL = libraries[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no library for variant \(variant.rawValue)")
        }
        return libraryURL
    }

    package static func machOFile(_ variant: Variant) async throws -> MachOFile {
        let libraryURL = try await libraryURL(variant)
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The `.release` variant loaded into the test process — only that one:
    /// the variants define the same class, and the Objective-C runtime keeps
    /// one of each.
    package static func loadedImage() async throws -> MachOImage {
        let libraryURL = try await libraryURL(.release)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}
