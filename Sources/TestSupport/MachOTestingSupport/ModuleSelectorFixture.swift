import Foundation
import MachOKit
import MachOFoundation
import Testing

/// An on-the-fly fixture for the SE-0491 module-selector spelling (evolution
/// proposal `module-selectors`): one reference of every shape the selector
/// rules treat differently.
///
/// - `Outer.Inner`, a type nested in a type of this module: every level
///   carries `ModuleSelectorFixture::`.
/// - `Duration.LocalFormat`, a type this module declares in an extension of
///   the standard library's `Duration`: the parent is `Swift::`, the nested
///   type names the module whose extension declared it — the case where the
///   two levels differ and the dotted spelling loses where the type is from.
/// - `Dictionary<String, Int>.Index` and `Box<Int>.Slot`, types nested in a
///   bound generic type.
/// - `any Marker & AnyObject`, whose `AnyObject` the printer spells itself.
/// - `some Collection<Int>`, the opaque type constraint the opaque type
///   provider spells.
/// - `Unique: ~Copyable` and `T: ~Copyable`, the suppressed conformances a
///   type header and a `where` clause spell.
/// - `[S.Element]`, an associated type of a type parameter, which no module
///   selector may qualify.
///
/// Nothing here needs a recent toolchain, so the fixture compiles with the
/// selected one — CI's included.
package enum ModuleSelectorFixture {
    package static let moduleName = "ModuleSelectorFixture"

    /// The `Anchor` class is ballast for the reader: a struct-only module
    /// compiles to a dylib with no `__DATA` segment (see
    /// `ExportedOnlyLibraryEvolutionFixtureTests`).
    package static let source = """
    public struct Outer {
        public struct Inner {
            public init() {}
        }
        public init() {}
    }

    public struct Box<Element> {
        public struct Slot {
            public init() {}
        }
        public var element: Element
    }

    extension Duration {
        public struct LocalFormat {
            public init() {}
        }
    }

    public struct Unique: ~Copyable {
        public var value: Int
    }

    public protocol Marker {}

    public struct Shapes {
        public var nested: Outer.Inner
        public var foreignNested: Duration.LocalFormat
        public var standardLibraryNested: Dictionary<String, Int>.Index
        public var genericNested: Box<Int>.Slot
        public var composition: any Marker & AnyObject

        public func opaqueCollection() -> some Collection<Int> { [1] }

        public func borrowAnything<Value: ~Copyable>(_ value: borrowing Value) {}

        public func elements<Elements: Sequence>(of sequence: Elements) -> [Elements.Element] { Array(sequence) }
    }

    extension Outer: Hashable {}

    extension Marker {
        public func describe() -> String { "" }
    }

    public protocol Container {
        associatedtype Item: Marker
        var item: Item { get }
    }

    public struct Conformer: Marker, Container {
        public var item: Conformer { self }
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

    /// Every name in `output` still qualified the dotted way by a module that
    /// `output` spells with a selector somewhere — what a print path writing a
    /// qualified name by hand, instead of through the type printer, leaves
    /// behind. Each entry is the qualified name and the line it is on.
    @available(macOS 13.0, *)
    package static func dottedQualifications(in output: String) -> [(qualifiedName: String, line: String)] {
        let selectedModuleNames = Set(output.matches(of: /([A-Za-z_][A-Za-z0-9_]*)::/).map { String($0.output.1) })
        var dottedQualifications: [(qualifiedName: String, line: String)] = []
        for line in output.split(separator: "\n") {
            // A whole qualified name at a time (`Swift::Duration.Foundation::LocalFormat`):
            // every `.`-separated level but the last must not be a bare module name.
            for qualifiedName in line.matches(of: /[A-Za-z_][A-Za-z0-9_]*(?:(?:\.|::)[A-Za-z_][A-Za-z0-9_]*)*/) {
                let levels = qualifiedName.output.split(separator: ".")
                if levels.dropLast().contains(where: { !$0.contains("::") && selectedModuleNames.contains(String($0)) }) {
                    dottedQualifications.append((String(qualifiedName.output), String(line)))
                }
            }
        }
        return dottedQualifications
    }

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
