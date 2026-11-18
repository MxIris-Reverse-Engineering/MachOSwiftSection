import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for the classes a source renamed for the Objective-C
/// runtime (evolution proposal `objc-custom-class-name`): one of every shape
/// that can carry `@objc(Name)` or `@_objcRuntimeName(Name)` — a class
/// renamed to another name and to its own Swift name, a nested one, one on the
/// native Swift object model, one whose superclass lives in another
/// resilience domain (no class object in `__objc_classlist`), an `@objc`
/// actor — beside a class that is not renamed, the negative control.
///
/// Three images: the Swift kit `libRenamedObjCClassFixtureKit` (library
/// evolution, so its `ResilientBase` is resilient to the client), the
/// Objective-C `libRenamedObjCClassFixtureBase` whose `RCFDriftBase` declares
/// its ivars in the implementation only — the compiler lays a Swift
/// subclass's fields out from the root's 8 bytes (the isa) and the ObjC
/// runtime slides them past the base's real size (objc4 `moveIvars`), the
/// case the static layout engine reproduces from the class's own
/// `class_ro_t.instanceStart` — and the client itself.
///
/// Two variants of the client:
/// - `.full`: every symbol present, the `To` thunks included.
/// - `.strippedLocals` (`strip -x`): the thunks are gone, as in every OS
///   framework; a member's `@objc` and `override` then come only from the
///   class's ObjC method table, which a renamed class used to be unreachable
///   from.
package enum RenamedObjCClassFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case full
        case strippedLocals
    }

    package static let moduleName = "RenamedObjCClassFixture"

    package static let kitModuleName = "RenamedObjCClassFixtureKit"

    package static let kitSource = """
    import Foundation

    open class ResilientBase: NSObject {
        public override init() { super.init() }
    }
    """

    package static let baseHeader = """
    #import <Foundation/Foundation.h>

    @interface RCFDriftBase : NSObject
    @end
    """

    package static let baseObjectiveCSource = """
    #import "RenamedObjCClassFixtureBase.h"

    // Ivars only the implementation declares: an instance size of 20, not a
    // multiple of a Swift subclass's widest field alignment.
    @implementation RCFDriftBase {
        int32_t first;
        int32_t second;
        int32_t third;
    }
    @end
    """

    package static let swiftSource = """
    import Foundation
    import \(kitModuleName)

    // Renamed: the class object's `class_ro_t` carries this name, not the
    // `_TtC…` mangling the ObjC-side indexes demangle to find a Swift class.
    @objc(RCFRenamedWidget) public class RenamedWidget: NSObject {
        public var count: Int = 0
        @objc public func poke() {}
        public override var description: String { "RenamedWidget" }
    }

    // Renamed to its own Swift name, AppKit's `NSScrollPocket` shape: without
    // the attribute the runtime name would have been the mangling.
    @objc(RCFSameNameWidget) public class RCFSameNameWidget: NSObject {}

    // Not renamed: the negative control.
    public class PlainWidget: NSObject {}

    // The native Swift object model, where `@objc` is not legal.
    @_objcRuntimeName(RCFNativeRoot) public class NativeRoot {}

    public enum Namespace {
        @objc(RCFNestedWidget) public class NestedWidget: NSObject {}
    }

    // A superclass in another resilience domain: the metadata is built at
    // runtime from a pattern, and no class object is in the class list.
    @objc(RCFResilientChild) public class ResilientChild: ResilientBase {}

    // Swift reference counting, yet derived from `NSObject`.
    @objc(RCFRenamedActor) public actor RenamedActor: NSObject {}

    // The extension's `@objc` members compile to a category on the renamed
    // class; `copy()` overrides an ObjC-inherited member from it.
    extension RenamedWidget {
        @objc public func pokeFromExtension() {}
        public override func copy() -> Any { self }
    }

    // Over the Objective-C base: the compiler lays the fields out from the
    // root's 8 bytes and the runtime slides them en masse past the base's
    // real size (20), rounded up to the widest field's alignment — `small`
    // lands at 24 and `wide` at 32, not where laying them out from 20 would
    // put them (20 and 24).
    @objc(RCFRenamedDrifter) public class RenamedDrifter: RCFDriftBase {
        public var small: Int8 = 0
        public var wide: Int64 = 0
    }

    public class PlainDrifter: RCFDriftBase {
        public var small: Int8 = 0
        public var wide: Int64 = 0
    }

    // Two same-named private classes, one per file, this one renamed: the
    // qualified name the ObjC-side lookups key on drops the private
    // discriminator, so the two must stay ambiguous.
    @objc(RCFPrivateTwin) private class PrivateTwin: NSObject {
        @objc func twinInFirstFile() {}
    }
    """

    package static let secondSwiftSource = """
    import Foundation

    // The other same-named private class, not renamed.
    private class PrivateTwin: NSObject {
        @objc func twinInSecondFile() {}
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
        package let baseLibrary: URL
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
            let baseHeaderURL = workingDirectory.appendingPathComponent("RenamedObjCClassFixtureBase.h")
            let baseSourceURL = workingDirectory.appendingPathComponent("RenamedObjCClassFixtureBase.m")
            let baseLibraryURL = workingDirectory.appendingPathComponent("libRenamedObjCClassFixtureBase.dylib")
            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            let secondSwiftSourceURL = workingDirectory.appendingPathComponent("FixtureSecondFile.swift")
            try kitSource.write(to: kitSourceURL, atomically: true, encoding: .utf8)
            try baseHeader.write(to: baseHeaderURL, atomically: true, encoding: .utf8)
            try baseObjectiveCSource.write(to: baseSourceURL, atomically: true, encoding: .utf8)
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)
            try secondSwiftSource.write(to: secondSwiftSourceURL, atomically: true, encoding: .utf8)

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
            try run(step: "clang (base)", [
                "clang", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation",
                "-install_name", baseLibraryURL.path,
                baseSourceURL.path, "-o", baseLibraryURL.path,
            ])

            var clientLibraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let clientLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                try run(step: "swiftc (\(variant.rawValue))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", moduleName,
                    "-import-objc-header", baseHeaderURL.path,
                    "-I", workingDirectory.path,
                    swiftSourceURL.path, secondSwiftSourceURL.path, kitLibraryURL.path, baseLibraryURL.path, "-framework", "Foundation",
                    "-o", clientLibraryURL.path,
                ])
                if variant == .strippedLocals {
                    try run(step: "strip (\(variant.rawValue))", ["strip", "-x", clientLibraryURL.path])
                }
                clientLibraries[variant] = clientLibraryURL
            }
            return CompiledLibraries(clientLibrariesByVariant: clientLibraries, kitLibrary: kitLibraryURL, baseLibrary: baseLibraryURL)
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
    /// the kit and the ObjC base as explicit files, the OS's classes through
    /// the running system's dyld shared cache.
    package static func dependencySearchPaths() throws -> [DependencySearchPath] {
        let libraries = try compilationResult.get()
        return [.machOFile(path: libraries.kitLibrary.path), .machOFile(path: libraries.baseLibrary.path), .systemDyldSharedCache]
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
