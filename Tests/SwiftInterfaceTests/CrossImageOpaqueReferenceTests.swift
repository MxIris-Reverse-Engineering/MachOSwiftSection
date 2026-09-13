import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftInterface

/// An associated-type witness built from a `some` result that lives in
/// ANOTHER image — the shape SwiftUI's `SidebarListBody.CollectionViewBody.Body`
/// has, whose `View.staticIf` is SwiftUICore's.
///
/// Two modules compiled on the fly: `ProbeCore` declares `HasBody` and an
/// extension method `helper() -> some Equatable`; `ProbeClient` conforms
/// `Outer` with `body: some Equatable { helper() }`. The underlying type of
/// `Outer.body` is `helper`'s opaque type, which the client's binary can only
/// reach through a bind to `ProbeCore`'s descriptor symbol — so the demangled
/// witness names it (`opaqueReturnTypeOf`) instead of pointing at it. Reading
/// it means locating `ProbeCore` and expanding the descriptor THERE.
///
/// Measured before this route existed: the dump printed
/// `<<opaque return type of (extension in ProbeCore):ProbeCore.HasBody.helper() -> some>>.0`
/// and the interface printed `typealias B = ProbeClient.Outer` — the
/// conformer itself, because `printOpaqueType` prints only the node's
/// argument list.
@Suite(.serialized)
struct CrossImageOpaqueReferenceTests {
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
        var description: String { "cross-image opaque fixture compilation failed:\n\(diagnostics)" }
    }

    private struct CompiledFixture {
        let coreLibraryURL: URL
        let clientLibraryURL: URL
    }

    private static let fixtureCompilationResult: Result<CompiledFixture, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CrossImageOpaqueFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let coreSourceURL = workingDirectory.appendingPathComponent("Core.swift")
            let clientSourceURL = workingDirectory.appendingPathComponent("Client.swift")
            try coreSource.write(to: coreSourceURL, atomically: true, encoding: .utf8)
            try clientSource.write(to: clientSourceURL, atomically: true, encoding: .utf8)
            let coreLibraryURL = workingDirectory.appendingPathComponent("libProbeCore.dylib")
            let clientLibraryURL = workingDirectory.appendingPathComponent("libProbeClient.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", "ProbeCore",
                "-target", "arm64-apple-macosx15.0",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/libProbeCore.dylib",
                coreSourceURL.path, "-o", coreLibraryURL.path,
            ])
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeClient",
                "-target", "arm64-apple-macosx15.0",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-lProbeCore",
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
    /// `__DATA` segment and the pinned MachOKit mis-walks its chained-fixup
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

    public struct Pair<First, Second> {
        public var first: First
        public var second: Second
        public init(first: First, second: Second) { self.first = first; self.second = second }
    }

    extension Pair: Equatable where First: Equatable, Second: Equatable {}
    """

    private static let clientSource = """
    import ProbeCore

    public final class ClientAnchor {}

    public struct Outer: HasBody {
        public init() {}
        public var body: some Equatable { helper() }
    }

    public struct Composite: HasBody {
        public init() {}
        public var body: some Equatable { Pair(first: helper(), second: "x") }
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

    /// The witnesses as the dump path resolves them, keyed by conformer.
    private func resolvedWitnessTexts(in machOFile: MachOFile) async throws -> [String: String] {
        var texts: [String: String] = [:]
        for associatedType in try machOFile.swift.associatedTypes {
            let conformer = await (try SymbolicDemangler.demangleType(for: associatedType.conformingTypeName, in: machOFile)).print(using: DemangleOptions.default)
            for record in associatedType.records where try record.name(in: machOFile) == "B" {
                let node = try SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machOFile), in: machOFile)
                texts[conformer] = await node.resolveOpaqueTypeCollectingConditionalCandidates(in: machOFile).node.print(using: DemangleOptions.default)
            }
        }
        return texts
    }

    @Test func theWitnessesExpandInTheImageThatDeclaresTheOpaqueType() async throws {
        let (client, corePath) = try loadClient()
        let texts = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [.machOFile(path: corePath)])) {
            try await resolvedWitnessTexts(in: client)
        }
        #expect(texts["ProbeClient.Outer"] == "Swift.Int")
        #expect(texts["ProbeClient.Composite"] == "ProbeCore.Pair<Swift.Int, Swift.String>")
    }

    /// The interface path shares the rewriter: the same two witnesses print
    /// as their types, not as the conformer.
    @Test func theInterfacePrintsTheExpandedWitnesses() async throws {
        let (client, corePath) = try loadClient()
        let interface = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [.machOFile(path: corePath)])) {
            let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: client)
            try await builder.prepare()
            return try await builder.printRoot().string
        }
        #expect(interface.contains("typealias B = Swift.Int"), "\(interface)")
        #expect(interface.contains("typealias B = ProbeCore.Pair<Swift.Int, Swift.String>"), "\(interface)")
        #expect(!interface.contains("typealias B = ProbeClient."), "\(interface)")
    }

    /// Without a search path that reaches `ProbeCore` the reference stays
    /// what it was — named, never the conformer and never a guess.
    @Test func withoutTheImageTheReferenceStaysNamed() async throws {
        let (client, _) = try loadClient()
        let texts = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try await resolvedWitnessTexts(in: client)
        }
        #expect(texts["ProbeClient.Outer"]?.contains("opaque return type of") == true, "\(String(describing: texts["ProbeClient.Outer"]))")
    }
}
