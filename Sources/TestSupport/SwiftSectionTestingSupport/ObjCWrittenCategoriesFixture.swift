import Foundation
import MachOFoundation
import MachOKit
import Testing

/// An on-the-fly fixture for the categories Objective-C code declares in an
/// image: a category that adopts a protocol is an extension of Swift's only
/// when the Swift compiler emitted it, and only an image Swift code went into
/// — its `objc_image_info` records a Swift version — can hold one.
///
/// Two variants of one library:
/// - `.objectiveCOnly`: Objective-C code alone, as every OS framework from
///   before Swift ships — OS X 10.9's AppKit, whose `NSString`, `NSURL`,
///   `NSAttributedString` and `NSFileVersion` categories adopt protocols and
///   were printed as Swift conformance extensions.
/// - `.mixed`: the same Objective-C code linked into a Swift module whose two
///   extensions of `DateFormatter` adopt `@objc` protocols, as a framework
///   carrying both languages does (AppKit since its overlay merged into it).
///   The linker merges the categories of one class: the image holds one
///   `NSDateFormatter` category, named after the first, listing the
///   Objective-C protocol and both Swift ones, and one `NSString` category.
package enum ObjCWrittenCategoriesFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case objectiveCOnly
        case mixed
    }

    package static let moduleName = "ObjCWrittenCategoriesFixture"

    package static let objectiveCSource = """
    #import <Foundation/Foundation.h>

    @protocol OWCObjectiveCWrittenAdoption <NSObject>
    - (void)owc_objectiveCWrittenPoke;
    @end

    // Categories Objective-C code declares, adopting a protocol: no Swift
    // extension stands behind them.
    @interface NSString (OWCObjectiveCWritten) <OWCObjectiveCWrittenAdoption>
    @end

    @implementation NSString (OWCObjectiveCWritten)
    - (void)owc_objectiveCWrittenPoke {}
    @end

    @interface NSDateFormatter (OWCObjectiveCWritten) <OWCObjectiveCWrittenAdoption>
    @end

    @implementation NSDateFormatter (OWCObjectiveCWritten)
    - (void)owc_objectiveCWrittenPoke {}
    @end
    """

    package static let swiftSource = """
    import Foundation

    @objc public protocol SwiftDeclaredAdoption {
        func swiftDeclaredPoke()
    }

    @objc public protocol SecondSwiftDeclaredAdoption {
        func secondSwiftDeclaredPoke()
    }

    // Two extensions of one class of another module: two categories, named
    // `\(moduleName)` and `\(moduleName)1`, before the linker merges them.
    extension DateFormatter: SwiftDeclaredAdoption {
        public func swiftDeclaredPoke() {}
    }

    extension DateFormatter: SecondSwiftDeclaredAdoption {
        public func secondSwiftDeclaredPoke() {}
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

    /// Compiled once per process; both variants share one working directory.
    private static let compilationResult: Result<[Variant: URL], any Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let objectiveCSourceURL = workingDirectory.appendingPathComponent("Categories.m")
            let objectiveCObjectURL = workingDirectory.appendingPathComponent("Categories.o")
            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try objectiveCSource.write(to: objectiveCSourceURL, atomically: true, encoding: .utf8)
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)

            let objectiveCOnlyLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(Variant.objectiveCOnly.rawValue).dylib")
            try run(step: "clang (\(Variant.objectiveCOnly.rawValue))", [
                "clang", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation",
                "-install_name", objectiveCOnlyLibraryURL.path,
                objectiveCSourceURL.path, "-o", objectiveCOnlyLibraryURL.path,
            ])

            let mixedLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(Variant.mixed.rawValue).dylib")
            try run(step: "clang (\(Variant.mixed.rawValue) object)", [
                "clang", "-c", "-fobjc-arc", objectiveCSourceURL.path, "-o", objectiveCObjectURL.path,
            ])
            try run(step: "swiftc (\(Variant.mixed.rawValue))", [
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", moduleName,
                "-Xlinker", "-install_name", "-Xlinker", mixedLibraryURL.path,
                swiftSourceURL.path, objectiveCObjectURL.path, "-framework", "Foundation",
                "-o", mixedLibraryURL.path,
            ])
            return [.objectiveCOnly: objectiveCOnlyLibraryURL, .mixed: mixedLibraryURL]
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
        try HostSlice.machOFile(at: libraryURL(variant))
    }

    /// A variant loaded into the test process. Both may be: they declare the
    /// same Objective-C protocol and categories, but no class, so the runtime
    /// keeps both images' records without a conflict.
    package static func loadedImage(_ variant: Variant) throws -> MachOImage {
        let libraryURL = try libraryURL(variant)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}
