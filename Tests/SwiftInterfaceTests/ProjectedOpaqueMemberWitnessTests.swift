import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftInterface

/// An associated-type witness that is a *member* of another module's opaque
/// archetype — `(↻τ.Element)` in the generics book's notation, spelled
/// `(@_opaqueReturnTypeOf("…", 0) __<Client>).Element` by the compiler's
/// interface printer.
///
/// `ProbeProjectionCore` (built with library evolution, so the client cannot
/// see the underlying type) declares `Source` with `Element == Output.Element`
/// and a protocol extension whose `produce()` returns `some IteratorProtocol`;
/// `ProbeProjectionClient.Client` conforms to both, so associated type
/// inference makes `Output` the opaque archetype and `Element` its
/// `.Element` member. Expanding the archetype gives
/// `IndexingIterator<[Int]>`, and the book's "Map type parameter into opaque
/// generic environment" algorithm projects the member through the underlying
/// conformance's type witness to `Int` (`IndexingIterator.Element` is
/// `Elements.Element`, and `Array<Int>.Element` is `Int`) — two hops through
/// libswiftCore's `__swift5_assocty` records. Before this batch the member
/// was left as `Swift.IndexingIterator<[Swift.Int]>.Element`.
@Suite(.serialized)
struct ProjectedOpaqueMemberWitnessTests {
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
        var description: String { "projected opaque member fixture compilation failed:\n\(diagnostics)" }
    }

    private struct CompiledFixture {
        let coreLibraryURL: URL
        let clientLibraryURL: URL
        let clientInterfaceText: String
    }

    private static let fixtureCompilationResult: Result<CompiledFixture, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProjectedOpaqueMemberFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let coreSourceURL = workingDirectory.appendingPathComponent("Core.swift")
            let clientSourceURL = workingDirectory.appendingPathComponent("Client.swift")
            try coreSource.write(to: coreSourceURL, atomically: true, encoding: .utf8)
            try clientSource.write(to: clientSourceURL, atomically: true, encoding: .utf8)
            let coreLibraryURL = workingDirectory.appendingPathComponent("libProbeProjectionCore.dylib")
            let clientLibraryURL = workingDirectory.appendingPathComponent("libProbeProjectionClient.dylib")
            let clientInterfaceURL = workingDirectory.appendingPathComponent("ProbeProjectionClient.swiftinterface")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", "ProbeProjectionCore",
                "-target", "arm64-apple-macosx15.0", "-enable-library-evolution",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/libProbeProjectionCore.dylib",
                coreSourceURL.path, "-o", coreLibraryURL.path,
            ])
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", "ProbeProjectionClient",
                "-target", "arm64-apple-macosx15.0", "-enable-library-evolution",
                "-emit-module-interface-path", clientInterfaceURL.path,
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/libProbeProjectionClient.dylib",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-lProbeProjectionCore",
                clientSourceURL.path, "-o", clientLibraryURL.path,
            ])
            return CompiledFixture(
                coreLibraryURL: coreLibraryURL,
                clientLibraryURL: clientLibraryURL,
                clientInterfaceText: try String(contentsOf: clientInterfaceURL, encoding: .utf8)
            )
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
    import ProbeProjectionCore

    public final class ClientAnchor {}

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

    /// `typealias <name> = …` as the compiler's own interface spells it, keyed
    /// by the bare name of the type the alias sits in. `Client` declares no
    /// opaque type of its own, so what the compiler names here is exactly
    /// what the binary's witness record names: `produce()`'s archetype.
    private func compilerSpellings(named associatedTypeName: String) throws -> [String: String] {
        let interfaceText = try Self.fixtureCompilationResult.get().clientInterfaceText
        var spellings: [String: String] = [:]
        var currentTypeName: String?
        let aliasPrefix = "public typealias \(associatedTypeName) = "
        for rawLine in interfaceText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            for declarationPrefix in ["public struct ", "public final class ", "public class ", "public enum "] where line.hasPrefix(declarationPrefix) {
                let declared = line.dropFirst(declarationPrefix.count)
                currentTypeName = declared.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "<" || $0 == "{" }).first.map(String.init)
            }
            if line.hasPrefix(aliasPrefix), let currentTypeName {
                spellings[currentTypeName] = String(line.dropFirst(aliasPrefix.count))
            }
        }
        return spellings
    }

    private func renderInterface(of machO: some MachOFieldLayoutRenderable) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The witness resolution for `Client`'s `Element`, as the dump and the
    /// indexer both obtain it.
    private func elementResolution(in machOFile: MachOFile) throws -> Node.OpaqueTypeResolution? {
        for associatedType in try machOFile.swift.associatedTypes {
            for record in associatedType.records where try record.name(in: machOFile) == "Element" {
                let witnessMangledName = try record.substitutedTypeName(in: machOFile)
                let node = try SymbolicDemangler.demangleType(for: witnessMangledName, in: machOFile)
                return node.resolveOpaqueTypeCollectingConditionalCandidates(witnessMangledName: witnessMangledName, conformingTypeName: associatedType.conformingTypeName, in: machOFile)
            }
        }
        return nil
    }

    /// With the image that declares the opaque type reachable, the member
    /// projects through the underlying conformance's type witnesses — two
    /// hops, the second through libswiftCore — and the interface prints the
    /// answer, not the member.
    @Test func withTheImageTheMemberProjectsToItsTypeWitness() async throws {
        let (client, corePath) = try loadClient()
        let interface = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [.machOFile(path: corePath), .systemDyldSharedCache])) {
            try await renderInterface(of: client)
        }
        #expect(interface.contains("typealias Output = Swift.IndexingIterator<[Swift.Int]>\n"), "\(interface)")
        #expect(interface.contains("typealias Element = Swift.Int\n"), "\(interface)")
    }

    /// Every hop is on record, so the dump can say where the answer came
    /// from: the origin member, the witness it resolved to, and the
    /// conformance whose record said so.
    @Test func theResolutionRecordsEveryProjectionHop() async throws {
        let (client, corePath) = try loadClient()
        let resolution = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [.machOFile(path: corePath), .systemDyldSharedCache])) {
            try #require(try elementResolution(in: client))
        }
        #expect(await resolution.node.print(using: DemangleOptions.default) == "Swift.Int")
        let hops = resolution.projectedMembers
        #expect(hops.count == 2, "\(hops.count) hops")
        #expect(hops.first?.conformingQualifiedName == "Swift.IndexingIterator", "\(String(describing: hops.first))")
        #expect(hops.first?.protocolQualifiedName == "Swift.IteratorProtocol", "\(String(describing: hops.first))")
        #expect(hops.last?.conformingQualifiedName == "Swift.Array", "\(String(describing: hops.last))")
        #expect(hops.last?.protocolQualifiedName == "Swift.Sequence", "\(String(describing: hops.last))")
        #expect(await hops.last?.witnessNode.print(using: DemangleOptions.default) == "Swift.Int")
    }

    /// Without the image the member stays a member of the named archetype,
    /// spelled the way the compiler's own interface spells it — with the
    /// parentheses the attribute grammar needs before `.Element`.
    @Test func withoutTheImageTheMemberIsSpelledLikeTheCompiler() async throws {
        let (client, _) = try loadClient()
        let elementSpellings = try compilerSpellings(named: "Element")
        let outputSpellings = try compilerSpellings(named: "Output")
        let interface = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try await renderInterface(of: client)
        }
        #expect(elementSpellings["Client"]?.hasPrefix("(@_opaqueReturnTypeOf(\"") == true, "\(elementSpellings)")
        #expect(interface.contains("typealias Element = " + (try #require(elementSpellings["Client"])) + "\n"), "\(interface)")
        #expect(interface.contains("typealias Output = " + (try #require(outputSpellings["Client"])) + "\n"), "\(interface)")
    }

    /// The in-process reader reaches the same answer: the archetype expands
    /// through the descriptor pointer dyld bound, and the projection walks
    /// the loaded images' witness records.
    @Test func inProcessTheMemberProjectsToItsTypeWitness() async throws {
        let fixture = try Self.fixtureCompilationResult.get()
        _ = fixture.coreLibraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        _ = fixture.clientLibraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        let machOImage = try #require(MachOImage(name: "libProbeProjectionClient"), "the client dylib did not load in-process")
        let interface = try await renderInterface(of: machOImage)
        #expect(interface.contains("typealias Output = Swift.IndexingIterator<[Swift.Int]>\n"), "\(interface)")
        #expect(interface.contains("typealias Element = Swift.Int\n"), "\(interface)")
    }
}
