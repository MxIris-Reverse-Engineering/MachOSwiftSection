import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclarationRendering
import SwiftDump
@_spi(Internals) import SwiftInspection
import SwiftThunkAnalysis

/// What the dump adds on top of the interface's spelling for an
/// associated-type witness built from another module's opaque archetype
/// (evolution proposal `opaque-reference-spelling-and-member-projection`):
/// a reference that could not be expanded carries the declaration it belongs
/// to as a trailing comment, and a member that was projected through
/// type-witness records gets a comment above the `typealias` naming every
/// hop. Neither is for a compiler; both are for the reader.
@Suite(.serialized)
struct OpaqueWitnessDumpAnnotationTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct FixtureCompilationError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "opaque witness dump fixture compilation failed:\n\(diagnostics)" }
    }

    private struct CompiledFixture {
        let coreLibraryURL: URL
        let clientLibraryURL: URL
    }

    private static let fixtureCompilationResult: Result<CompiledFixture, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueWitnessDumpFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let coreSourceURL = workingDirectory.appendingPathComponent("Core.swift")
            let clientSourceURL = workingDirectory.appendingPathComponent("Client.swift")
            try coreSource.write(to: coreSourceURL, atomically: true, encoding: .utf8)
            try clientSource.write(to: clientSourceURL, atomically: true, encoding: .utf8)
            let coreLibraryURL = workingDirectory.appendingPathComponent("libProbeDumpCore.dylib")
            let clientLibraryURL = workingDirectory.appendingPathComponent("libProbeDumpClient.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", "ProbeDumpCore",
                "-target", "arm64-apple-macosx15.0", "-enable-library-evolution",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/libProbeDumpCore.dylib",
                coreSourceURL.path, "-o", coreLibraryURL.path,
            ])
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeDumpClient",
                "-target", "arm64-apple-macosx15.0",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-lProbeDumpCore",
                clientSourceURL.path, "-o", clientLibraryURL.path,
            ])
            return CompiledFixture(coreLibraryURL: coreLibraryURL, clientLibraryURL: clientLibraryURL)
        }
    }()

    private static func run(swiftcArguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc"] + swiftcArguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain before waiting, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    /// Both modules carry a class: a struct-only fixture dylib has no
    /// `__DATA` segment and MachOKit before 0.52.103 mis-walked its chained-fixup
    /// pages.
    private static let coreSource = """
    public final class CoreAnchor {}

    public protocol HasBody {
        associatedtype B
        var body: B { get }
    }

    extension HasBody {
        public func helper() -> some Equatable { 1 }
    }

    public protocol Source {
        associatedtype Output: IteratorProtocol
        associatedtype Element where Element == Output.Element
        func produce() -> Output
    }

    public protocol DefaultSource {}

    extension DefaultSource {
        public func produce() -> some IteratorProtocol { [1].makeIterator() }
    }
    """

    private static let clientSource = """
    import ProbeDumpCore

    public final class ClientAnchor {}

    public struct Outer: HasBody {
        public init() {}
        public var body: some Equatable { helper() }
    }

    public struct Client: DefaultSource, Source {
        public init() {}
    }
    """

    private func loadClient() throws -> (client: MachOFile, corePath: String) {
        let fixture = try Self.fixtureCompilationResult.get()
        switch try File.loadFromFile(url: fixture.clientLibraryURL) {
        case .machO(let machOFile):
            return (machOFile, fixture.coreLibraryURL.path)
        case .fat(let fatFile):
            return (try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }), fixture.coreLibraryURL.path)
        }
    }

    /// The dump of every conformance in the client, keyed by
    /// `Conformer: Protocol`.
    private func dumpedConformances(in machOFile: MachOFile) async throws -> [String: String] {
        var dumps: [String: String] = [:]
        for associatedType in try machOFile.swift.associatedTypes {
            let conformer = await (try SymbolicDemangler.demangleType(for: associatedType.conformingTypeName, in: machOFile)).print(using: DemangleOptions.default)
            let protocolName = await (try SymbolicDemangler.demangleType(for: associatedType.protocolTypeName, in: machOFile)).print(using: DemangleOptions.default)
            dumps["\(conformer): \(protocolName)"] = try await associatedType.dump(using: .demangleOptions(.default), in: machOFile).string
        }
        return dumps
    }

    @Test func anUnexpandedReferenceNamesItsOwnerDeclarationInAComment() async throws {
        let (client, _) = try loadClient()
        let dumps = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try await dumpedConformances(in: client)
        }
        let dump = try #require(dumps["ProbeDumpClient.Outer: ProbeDumpCore.HasBody"], "\(dumps.keys)")
        #expect(dump.contains("typealias B = @_opaqueReturnTypeOf(\"$s"), "\(dump)")
        #expect(dump.contains("__<ProbeDumpClient.Outer> /* (extension in ProbeDumpCore):ProbeDumpCore.HasBody.helper() -> some */"), "\(dump)")
    }

    @Test func aProjectedMemberExplainsItsHopsAboveTheTypealias() async throws {
        let (client, corePath) = try loadClient()
        let dumps = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [.machOFile(path: corePath), .systemDyldSharedCache])) {
            try await dumpedConformances(in: client)
        }
        let dump = try #require(dumps["ProbeDumpClient.Client: ProbeDumpCore.Source"], "\(dumps.keys)")
        #expect(dump.contains("typealias Element = Swift.Int\n"), "\(dump)")
        #expect(dump.contains("// Element is projected through associated type witnesses:"), "\(dump)")
        #expect(dump.contains("(witness of Swift.IndexingIterator: Swift.IteratorProtocol)"), "\(dump)")
        #expect(dump.contains(" is Swift.Int (witness of Swift.Array: Swift.Sequence)"), "\(dump)")
    }
}
