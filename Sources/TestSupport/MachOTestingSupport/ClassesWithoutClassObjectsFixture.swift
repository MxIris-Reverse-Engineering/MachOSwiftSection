import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for the Swift classes an image keeps no class
/// object for (evolution proposal `objc-classes-without-class-objects`): one
/// of each metadata strategy that leaves a class out of `__objc_classlist` —
/// generic classes, a class whose superclass lives in another resilience
/// domain, a class with generic ancestry — beside a class with a class
/// object, the negative control.
///
/// Two images: the Swift kit `libClassesWithoutClassObjectsFixtureKit`
/// (library evolution, so its `ResilientBase` is resilient to the client)
/// and the client itself, in two variants:
/// - `.full`: every symbol present, the `To` thunks and the class stubs'
///   `…CMs` symbols included.
/// - `.strippedLocals` (`strip -x`): as in every OS framework, the thunks
///   and the non-public stub of the class with generic ancestry are gone.
package enum ClassesWithoutClassObjectsFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case full
        case strippedLocals
    }

    package static let moduleName = "ClassesWithoutClassObjectsFixture"

    package static let kitModuleName = "ClassesWithoutClassObjectsFixtureKit"

    package static let kitSource = """
    import Foundation

    open class ResilientBase: NSObject {
        public override init() { super.init() }
    }
    """

    package static let swiftSource = """
    import Foundation
    import \(kitModuleName)

    // Generic: the `class_ro_t` template sits in the generic metadata
    // pattern, its name a null pointer.
    public class GenericWidget<Element>: NSObject {
        public override var description: String { "GenericWidget" }
        @objc public func poke() {}
        @objc public class func classPoke() {}
    }

    public enum Namespace {
        // Two parameters at one depth.
        public class NestedGenericWidget<Key, Value>: NSObject {
            @objc public func nestedPoke() {}
        }
    }

    // Generic on the native object model: the runtime gives it `SwiftObject`
    // for a superclass.
    public class GenericNativeRoot<Element> {
        public init() {}
    }

    // A superclass in another resilience domain: the metadata is allocated
    // from a pattern at runtime, and the descriptor records the class stub.
    public class ResilientChild: ResilientBase {
        public override var description: String { "ResilientChild" }
        @objc public func resilientPoke() {}
    }

    // Generic ancestry: statically emitted metadata the runtime initializes
    // first, registered through a stub only its `…CMs` symbol names.
    public class ConcreteSubclass: GenericWidget<Int> {
        public override var description: String { "ConcreteSubclass" }
        @objc public func concretePoke() {}
    }

    // Generic ancestry on the native object model: no stub at all, and
    // nothing `__objc_stublist` registers.
    public class NativeConcreteSubclass: GenericNativeRoot<Int> {}

    // A class object in the class list: the negative control.
    public class PlainWidget: NSObject {
        @objc public func plainPoke() {}
    }
    """

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

    package struct CompiledLibraries: Sendable {
        package let clientLibrariesByVariant: [Variant: URL]
        package let kitLibrary: URL
    }

    /// Compiled once per process; every variant shares one working directory.
    private static let compilationResult: Result<CompiledLibraries, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let kitSourceURL = workingDirectory.appendingPathComponent("Kit.swift")
            let kitLibraryURL = workingDirectory.appendingPathComponent("lib\(kitModuleName).dylib")
            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try kitSource.write(to: kitSourceURL, atomically: true, encoding: .utf8)
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)

            // Install names are the absolute output paths, which is what the
            // client's load commands then spell — so the in-process leg loads
            // with no rpath, and a resolver finds them by path.
            try run(step: "swiftc (kit)", [
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                "swiftc", "-swift-version", "5", "-emit-library", "-enable-library-evolution",
                "-emit-module", "-emit-module-path", workingDirectory.appendingPathComponent("\(kitModuleName).swiftmodule").path,
                "-module-name", kitModuleName,
                "-Xlinker", "-install_name", "-Xlinker", kitLibraryURL.path,
                kitSourceURL.path, "-o", kitLibraryURL.path,
            ])

            var clientLibraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let clientLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                try run(step: "swiftc (\(variant.rawValue))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", moduleName,
                    "-I", workingDirectory.path,
                    swiftSourceURL.path, kitLibraryURL.path, "-framework", "Foundation",
                    "-o", clientLibraryURL.path,
                ])
                if variant == .strippedLocals {
                    try run(step: "strip (\(variant.rawValue))", ["strip", "-x", clientLibraryURL.path])
                }
                clientLibraries[variant] = clientLibraryURL
            }
            return CompiledLibraries(clientLibrariesByVariant: clientLibraries, kitLibrary: kitLibraryURL)
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
        guard let libraryURL = libraries.clientLibrariesByVariant[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no library for variant \(variant.rawValue)")
        }
        return libraryURL
    }

    /// The search paths under which the client's whole world is reachable:
    /// the kit as an explicit file, the OS's classes through the running
    /// system's dyld shared cache.
    package static func dependencySearchPaths() throws -> [DependencySearchPath] {
        let libraries = try compilationResult.get()
        return [.machOFile(path: libraries.kitLibrary.path), .systemDyldSharedCache]
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

    /// The `.full` client loaded into the test process — only that variant:
    /// both define the same ObjC classes, and the runtime keeps one of each.
    package static func loadedImage() throws -> MachOImage {
        let libraryURL = try libraryURL(.full)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}
