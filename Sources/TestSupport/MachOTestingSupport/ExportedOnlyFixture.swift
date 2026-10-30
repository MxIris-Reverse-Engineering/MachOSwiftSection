import Foundation
import MachOKit
import MachOFoundation
import Testing

/// An on-the-fly fixture for the exported-only filter (evolution proposals
/// `exported-only-interface` and `exported-only-marking-mode`) over
/// `internal` declarations — the shape `SymbolTestsCore` cannot pin, because
/// that fixture is built with `ENABLE_TESTABILITY` and exports its
/// internals. This module is compiled with `-enable-library-evolution` and
/// WITHOUT `-enable-testing`, so every `internal` declaration is a local
/// symbol and the filter has a definitive negative to act on for: a type, a
/// nested type, a protocol and its default implementation, a method, a
/// stored property, a global, a conformance to an internal protocol, and a
/// constrained extension whose members are all internal. It also extends a
/// C-imported type (`CGPoint`), whose descriptor the module emits as a copy
/// of its own and never exports.
///
/// The last group is for a marked print: definitions whose body keeps its
/// nested types but nothing after them once the filter is on — a type
/// (`Holder`), a type whose stored property is internal (`FieldHolder`), a
/// caseless enum (`Namespace`) and an extension of another module's type
/// (`Int`) — and one that keeps nothing at all (`Hidden`).
///
/// `UnexportedParent` is public in the source, but the link leaves its type
/// symbols out of the export trie (`unexportedSymbolNames`) while its nested
/// `ExportedNested` keeps them: an exported type nested in one that is not,
/// the shape an export list gives an OS framework — Foundation's
/// `LocalePreferences.ICUSymbolsAndStrings`, `package` in the source like its
/// parent, is exported while `LocalePreferences` is not.
package enum ExportedOnlyFixture {
    package static let moduleName = "ExportedOnlyFixture"

    /// The symbols the link leaves out of the export trie: the type
    /// descriptor, metadata accessor and type metadata of `UnexportedParent`.
    package static let unexportedSymbolNames = [
        "_$s19ExportedOnlyFixture16UnexportedParentVMn",
        "_$s19ExportedOnlyFixture16UnexportedParentVMa",
        "_$s19ExportedOnlyFixture16UnexportedParentVN",
    ]

    /// The `Anchor` class is load-bearing fixture ballast: a struct-only
    /// module compiles to a dylib with no `__DATA` segment, whose
    /// chained-fixup pages MachOKit releases before 0.52.103 mis-walked (see
    /// `DiffMemberIndentationTests`). `@inline(never)` keeps the internal
    /// members' symbols from being folded away.
    package static let source = """
    import CoreGraphics
    public struct PublicShape {
        public var title: String
        var internalNote: String
        public init(title: String, internalNote: String) {
            self.title = title
            self.internalNote = internalNote
        }
        public func publicMethod() {}
        @inline(never) func internalMethod() {}
        public struct PublicNested {}
        struct InternalNested {}
    }
    struct InternalShape {
        var value: Int
    }
    extension InternalShape {
        @inline(never) func orphanMethod() {}
    }
    public protocol PublicContract {
        func requirement()
    }
    protocol InternalContract {
        func hidden()
    }
    extension InternalContract {
        @inline(never) func hiddenDefault() {}
    }
    extension PublicShape: PublicContract {
        public func requirement() {}
    }
    extension PublicShape: InternalContract {
        @inline(never) func hidden() {}
    }
    public struct PublicBox<Element> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }
    extension PublicBox where Element == Int {
        @inline(never) func internalConstrainedMember() {}
    }
    extension PublicBox where Element == String {
        public func publicConstrainedMember() {}
    }
    public struct PublicPair<Element> {
        public var first: Element
        public var second: Element
        public init(first: Element, second: Element) {
            self.first = first
            self.second = second
        }
    }
    extension PublicPair where Element == Int {
        @inline(never) func internalOnlyConstrainedMember() {}
    }
    public enum PublicEnum {
        case alpha
        case beta
    }
    public class Anchor {
        public func run() {}
    }
    public func publicGlobal() {}
    @inline(never) func internalGlobal() {}
    extension CGPoint: PublicContract {
        public func requirement() {}
    }
    extension CGPoint {
        public func publicCImportedTypeMember() {}
    }
    public struct Holder {
        public struct Nested {}
        @inline(never) func internalHelper() {}
    }
    public struct FieldHolder {
        public struct Nested {}
        var internalStorage: Int = 0
    }
    public enum Namespace {
        public struct Member {}
        @inline(never) static func internalHelper() {}
    }
    extension Int {
        public struct ExportedOnlyFixtureNested {}
        @inline(never) func exportedOnlyFixtureInternalHelper() {}
    }
    public struct Hidden {
        struct InternalNested {}
        @inline(never) func internalHelper() {}
    }
    public struct UnexportedParent {
        public struct ExportedNested {
            public init() {}
        }
        public init() {}
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

            let sourceURL = workingDirectory.appendingPathComponent("\(moduleName).swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-enable-library-evolution",
                "-module-name", moduleName,
                sourceURL.path, "-o", libraryURL.path,
            ] + unexportedSymbolNames.flatMap { ["-Xlinker", "-unexported_symbol", "-Xlinker", $0] }
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
