import Foundation
import MachOKit
import MachOFoundation
import Testing

/// An on-the-fly fixture for spelling existential types with the `any`
/// keyword (evolution proposal `existential-any`): one stored property or
/// parameter of every shape the keyword, or the parentheses it needs, treats
/// differently.
///
/// - `any Marker`, `any Marker & SecondMarker`, `any Marker & AnyObject`,
///   `any Base & Marker`: a protocol, a composition, a class-bound and a
///   superclass-bound existential, each with one keyword.
/// - `Any` and `AnyObject`: bare, as the compiler leaves them.
/// - `any Collection`: a protocol with associated types, which the compiler
///   warns must be written with `any`.
/// - `(any Marker)?`, `(any Error)?`, `Any?`: an optional parenthesizes the
///   existential written with the keyword, and only that one.
/// - `any Marker.Type`, `any (Marker & SecondMarker).Type`, `Any.Type`,
///   `AnyObject.Type`, `(any Marker.Type)?`: existential metatypes, every one
///   with the keyword — the compiler writes `any Any.Type`.
/// - `(any Marker).Type`: the metatype of the existential itself, which the
///   bare spelling writes as `Marker.Protocol`.
/// - `any Boxed<Int>`, `(any Boxed<String>)?`, `any Boxed<Int>.Type`,
///   `(any Boxed<Int>.Type)?`: a constrained existential, which a field record
///   spells as an extended existential shape plus its arguments, and which
///   takes the keyword — and the parentheses an optional needs — whether or
///   not the other existentials do.
/// - an array of existentials, a closure taking and returning one, a variadic
///   and an `inout` parameter, a parameterized existential parameter, and an
///   opaque type constrained by an existential argument.
///
/// Nothing here needs a recent toolchain, so the fixture compiles with the
/// selected one — CI's included.
package enum ExistentialAnyFixture {
    package static let moduleName = "ExistentialAnyFixture"

    /// The `Anchor` class is ballast for the reader: a struct-only module
    /// compiles to a dylib with no `__DATA` segment (see
    /// `ExportedOnlyLibraryEvolutionFixtureTests`).
    package static let source = """
    public protocol Marker {}

    public protocol SecondMarker {}

    public protocol Boxed<Wrapped> {
        associatedtype Wrapped
        var wrapped: Wrapped { get }
    }

    public class Base {}

    public struct Shapes {
        public var single: any Marker
        public var composition: any Marker & SecondMarker
        public var classBound: any Marker & AnyObject
        public var superclassBound: any Base & Marker
        public var anything: Any
        public var anyObject: AnyObject
        public var collection: any Collection
        public var optional: (any Marker)?
        public var optionalComposition: (any Marker & SecondMarker)?
        public var optionalError: (any Error)?
        public var optionalAnything: Any?
        public var existentialMetatype: any Marker.Type
        public var compositionMetatype: any (Marker & SecondMarker).Type
        public var anythingMetatype: Any.Type
        public var anyObjectMetatype: AnyObject.Type
        public var optionalExistentialMetatype: (any Marker.Type)?
        public var protocolMetatype: (any Marker).Type
        public var constrained: any Boxed<Int>
        public var optionalConstrained: (any Boxed<String>)?
        public var constrainedMetatype: any Boxed<Int>.Type
        public var optionalConstrainedMetatype: (any Boxed<Int>.Type)?
        public var existentialArray: [any Marker]
        public var existentialFunction: (any Marker) -> any SecondMarker

        public func accept(_ value: any Marker, _ values: any Marker...) {}

        public func acceptInout(_ value: inout any Marker) {}

        public func acceptConstrained(_ value: any Boxed<Int>) {}

        public func opaqueSequence() -> some Sequence<any Marker> { [any Marker]() }
    }

    public class Anchor {
        public func run() {}
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture compilation failed:\n\(diagnostics)" }
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

    /// Compiled once per process.
    private static let compilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                "swiftc", "-swift-version", "5", "-emit-library", "-enable-library-evolution",
                "-module-name", moduleName,
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    package static func machOFile() throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: try compilationResult.get()) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }
}
