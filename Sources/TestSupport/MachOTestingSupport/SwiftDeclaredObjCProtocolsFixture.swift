import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for the `@objc` protocols a Swift module declares
/// (evolution proposal `swift-declared-objc-protocols`): the compiler emits
/// no Swift protocol descriptor for them and no Swift symbol for any of their
/// requirements, only an Objective-C protocol record and a field descriptor
/// of kind `ObjCProtocol`.
///
/// Two images. The kit `libSwiftDeclaredObjCProtocolsFixtureKit` declares two
/// `@objc` protocols — one renamed — that the client adopts, so the client
/// holds Swift-emitted copies of records it does not define. The client
/// declares one protocol of each shape (selectors the compiler derives,
/// renamed to its own Swift name, renamed to another name, refining another,
/// internal, declared in a type) and the classes that adopt them, in three
/// variants:
/// - `.full`: reflection metadata and every symbol present.
/// - `.withoutReflectionMetadata` (`-disable-reflection-metadata`): no
///   `__swift5_fieldmd`, so only the records' runtime names say which
///   protocols are the client's.
/// - `.strippedLocals` (`strip -x`): as every OS framework ships.
package enum SwiftDeclaredObjCProtocolsFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case full
        case withoutReflectionMetadata
        case strippedLocals
    }

    package static let moduleName = "SwiftDeclaredObjCProtocolsFixture"

    package static let kitModuleName = "SwiftDeclaredObjCProtocolsFixtureKit"

    package static let kitSource = """
    import Foundation

    @objc public protocol KitObserver {
        func observe()
    }

    @objc(KITRenamedObserver) public protocol RenamedKitObserver {
        func renamedObserve()
    }
    """

    package static let swiftSource = """
    import Foundation
    import \(kitModuleName)

    // Swift names only: the compiler derives every selector.
    @objc public protocol DerivedSelectors: NSObjectProtocol {
        init(identifier: String)
        func name(for object: Any) -> String
        func teamName(for teamIdentifier: String) throws -> String
        func hangPoints(input: NSObject) throws -> [String]
        func perform(_ action: String, with object: Any?)
        func download(identifier: String, completion: @escaping (URL?, Error?) -> Void)
        func token() throws -> String
        func reload()
        var title: String { get }
        var isEnabled: Bool { get set }
        subscript(index: Int) -> Any { get set }
        static func makeDefault() -> NSObject
        static var shared: NSObject { get }
        @objc optional func scroll(to index: Int, animated: Bool)
        @objc optional var optionalCount: Int { get }
    }

    // Renamed to its own Swift name, Apple's usual shape.
    @objc(SameNameRenamed) public protocol SameNameRenamed {
        func ping()
    }

    // Renamed to another name: nothing pairs the record with the declaration.
    @objc(PRBDifferentlyNamed) public protocol DifferentlyNamed {
        @objc(nameForObject:) func name(for object: Any) -> String
        @objc(isEnabled) var enabled: Bool { get }
    }

    @objc public protocol RefinedProtocol: SameNameRenamed {
        func refine()
    }

    @objc protocol InternalProtocol {
        func internalRequirement()
    }

    // Declared in a type (SE-0404): `_TtPC…` names it, with its parent.
    public class Outer: NSObject {
        @objc public protocol NestedProtocol {
            func nestedRequirement()
        }
    }

    extension DerivedSelectors {
        public func describe() -> String { title }
    }

    // Adopted in the class declaration: `class_ro_t` lists the protocols,
    // an imported one among them.
    public class Conformer: NSObject, SameNameRenamed, NSCopying {
        public func ping() {}
        public func copy(with zone: NSZone? = nil) -> Any { self }
    }

    // Adopted in an extension: the category lists the protocol.
    public class ExtensionConformer: NSObject {}

    extension ExtensionConformer: RefinedProtocol {
        public func ping() {}
        public func refine() {}
    }

    // Adopts the kit's protocols: the client holds copies of their records.
    public class KitObserverConformer: NSObject, KitObserver, RenamedKitObserver {
        public func observe() {}
        public func renamedObserve() {}
    }

    final class InternalConformer: NSObject, InternalProtocol {
        func internalRequirement() {}
    }

    public class NestedConformer: NSObject, Outer.NestedProtocol {
        public func nestedRequirement() {}
    }

    public func makeInternalConformer() -> AnyObject {
        InternalConformer()
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

            // Install names are the absolute output paths, so the in-process
            // leg loads with no rpath.
            try run(step: "swiftc (kit)", [
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                "swiftc", "-swift-version", "5", "-emit-library",
                "-emit-module", "-emit-module-path", workingDirectory.appendingPathComponent("\(kitModuleName).swiftmodule").path,
                "-module-name", kitModuleName,
                "-Xlinker", "-install_name", "-Xlinker", kitLibraryURL.path,
                kitSourceURL.path, "-o", kitLibraryURL.path,
            ])

            var clientLibraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let clientLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                var arguments = [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", moduleName,
                    "-I", workingDirectory.path,
                    swiftSourceURL.path, kitLibraryURL.path, "-framework", "Foundation",
                    "-o", clientLibraryURL.path,
                ]
                if variant == .withoutReflectionMetadata {
                    arguments += ["-Xfrontend", "-disable-reflection-metadata"]
                }
                try run(step: "swiftc (\(variant.rawValue))", arguments)
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
    /// the kit as an explicit file, the OS through the running system's dyld
    /// shared cache.
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
    /// every variant defines the same Objective-C classes, and the runtime
    /// keeps one of each.
    package static func loadedImage() throws -> MachOImage {
        let libraryURL = try libraryURL(.full)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}
