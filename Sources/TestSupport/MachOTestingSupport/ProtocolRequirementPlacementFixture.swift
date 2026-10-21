import Foundation
import MachOKit
import MachOFoundation
import Testing

/// An on-the-fly fixture for how a protocol's requirement signature prints
/// (evolution proposal `protocol-requirement-placement`).
///
/// The binary records a protocol's requirements only in their canonical
/// form, never where the source wrote them, so each protocol here collects
/// the requirement shapes the printer has to tell apart:
///
/// - `CompositeRequirements`: same-type and superclass requirements whose
///   right-hand side is a composite type — an array, a tuple, an optional, a
///   bound generic class, an array of `Self`, and an array of a member whose
///   mangling names the protocol declaring it (`Seventh` conforms to two
///   protocols, so `Seventh.Element` is qualified with `Sequence`).
/// - `DirectRequirements`: conformance, superclass and layout requirements on
///   exactly `Self.Item`, one associated type with two, and a member of a
///   member (`Nested.Element`).
/// - `SameTypeRequirements`: same-type requirements between two associated
///   types (canonically `Self.First == Self.Second.Target`) and with `Self`
///   (`Self == Self.Third.Target`).
/// - `RecursiveRequirements`: `Child.Leaf: Hashable` on a protocol whose
///   `Child` conforms to it again — the shape the compiler's own printer
///   attaches to `Leaf`, changing its meaning.
/// - `RefinedRequirements` and `InheritedOnlyRequirements`: requirements on a
///   refined protocol's associated type (`Element`), which no
///   `associatedtype` of the protocol itself declares.
/// - `SubjectOnlyRequirements`: a superclass requirement on the refined
///   `Element` whose superclass names the protocol's own `First`
///   (`Element: GenericBase<First>`). A conformance, superclass or layout
///   requirement goes by its subject alone, as in the compiler's own
///   printer, so this one stays on the protocol.
/// - `ClassBoundRequirements` and `MenuRequirements`: requirements on `Self`
///   (`AnyObject`, a refined protocol) beside one on an associated type.
///
/// The declarations those protocols mention live in `supportSource`, apart
/// from `protocolSource`, so a printed form of the protocols compiles against
/// the same declarations again (`machOFile(compiling:)`).
package enum ProtocolRequirementPlacementFixture {
    package static let moduleName = "ProtocolRequirementPlacementFixture"

    /// `Anchor` is ballast for the reader: a module without a class compiles
    /// to a dylib with no `__DATA` segment (see
    /// `ExportedOnlyLibraryEvolutionFixtureTests`).
    package static let supportSource = """
    public protocol Marker {}

    public class BaseClass {}

    public class GenericBase<Element> {}

    public protocol Pointing {
        associatedtype Target
    }

    public final class Anchor {
        public func run() {}
    }
    """

    /// The protocols of `protocolSource`, in source order.
    package static let protocolNames = [
        "CompositeRequirements",
        "DirectRequirements",
        "SameTypeRequirements",
        "RecursiveRequirements",
        "RefinedRequirements",
        "InheritedOnlyRequirements",
        "SubjectOnlyRequirements",
        "ClassBoundRequirements",
        "MenuRequirements",
    ]

    package static let protocolSource = """
    public protocol CompositeRequirements {
        associatedtype First
        associatedtype Second where Second == [First]
        associatedtype Third where Third == (First, [First])
        associatedtype Fourth where Fourth == First?
        associatedtype Fifth: GenericBase<First>
        associatedtype Sixth where Sixth == [Self]
        associatedtype Seventh: Sequence, Marker
        associatedtype Eighth where Eighth == [Seventh.Element]
    }

    public protocol DirectRequirements {
        associatedtype Conforming: Marker, Hashable
        associatedtype Subclass: BaseClass
        associatedtype ClassBound: AnyObject
        associatedtype ClassAndProtocol: BaseClass, Marker
        associatedtype Nested: Sequence where Nested.Element: Marker
        associatedtype Concrete where Concrete == Int
    }

    public protocol SameTypeRequirements {
        associatedtype First
        associatedtype Second: Pointing where Second.Target == First
        associatedtype Third: Pointing where Third.Target == Self
    }

    public protocol RecursiveRequirements {
        associatedtype Child: RecursiveRequirements where Child.Leaf: Hashable
        associatedtype Leaf
    }

    public protocol RefinedRequirements: Sequence where Element: Marker {
        associatedtype Storage: Collection where Storage.Element == Element
    }

    public protocol InheritedOnlyRequirements: Sequence where Element: Hashable {}

    public protocol SubjectOnlyRequirements: Sequence where Element: GenericBase<First> {
        associatedtype First
    }

    public protocol ClassBoundRequirements: AnyObject {
        associatedtype Item: AnyObject
    }

    public protocol MenuRequirements: Identifiable where MenuItem: Marker {
        associatedtype MenuItem
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture compilation failed:\n\(diagnostics)" }
    }

    /// The fixture: `supportSource` and `protocolSource` in one library.
    package static func machOFile() throws -> MachOFile {
        try machOFile(compiling: protocolSource)
    }

    /// `supportSource` and `protocolDeclarations` compiled into one library
    /// named `moduleName`, as the fixture itself is, so every name a printed
    /// protocol mentions resolves to the same declaration again. Each
    /// distinct source compiles once per process.
    package static func machOFile(compiling protocolDeclarations: String) throws -> MachOFile {
        let libraryURL = try CompiledLibraries.shared.libraryURL(for: supportSource + "\n\n" + protocolDeclarations)
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
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

    private final class CompiledLibraries: @unchecked Sendable {
        static let shared = CompiledLibraries()

        private let lock = NSLock()

        private var libraryURLsBySource: [String: URL] = [:]

        /// Compiles under the lock: two tests asking for the same source wait
        /// for one compiler run. The wait is on `swiftc`, never on a pool
        /// thread.
        func libraryURL(for source: String) throws -> URL {
            lock.lock()
            defer { lock.unlock() }
            if let libraryURL = libraryURLsBySource[source] {
                return libraryURL
            }
            let libraryURL = try Self.compile(source)
            libraryURLsBySource[source] = libraryURL
            return libraryURL
        }

        private static func compile(_ source: String) throws -> URL {
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
                "swiftc", "-swift-version", "5", "-emit-library",
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
    }
}
