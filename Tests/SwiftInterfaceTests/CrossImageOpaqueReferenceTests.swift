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

    /// How the two unexpandable witnesses must be spelled: the attribute the
    /// compiler's interface printer uses to name an opaque archetype of
    /// another declaration, over `helper()`'s mangling.
    ///
    /// Not what `swiftc -emit-module-interface` writes for this client — that
    /// names `Outer.body`'s OWN opaque type
    /// (`@_opaqueReturnTypeOf("$s11ProbeClient5OuterV4bodyQrvp", 0) __`),
    /// because the interface describes declarations, while the binary's
    /// witness record has already had `body`'s underlying type substituted
    /// in (same module, so visible to IRGen) and names `helper()`'s. The
    /// spelling is the compiler's; the reference is one level deeper than
    /// the compiler's interface would show.
    private static let helperReferenceForOuter = "@_opaqueReturnTypeOf(\"$s9ProbeCore7HasBodyPAAE6helperQryF\", 0) __<ProbeClient.Outer>"
    private static let helperReferenceForComposite = "ProbeCore.Pair<@_opaqueReturnTypeOf(\"$s9ProbeCore7HasBodyPAAE6helperQryF\", 0) __<ProbeClient.Composite>, Swift.String>"

    /// The witnesses as the dump path resolves them, keyed by conformer.
    private func resolvedWitnessTexts(in machOFile: MachOFile, spelling: OpaqueReferenceSpelling = .textualInterface) async throws -> [String: String] {
        var texts: [String: String] = [:]
        for associatedType in try machOFile.swift.associatedTypes {
            let conformer = await (try SymbolicDemangler.demangleType(for: associatedType.conformingTypeName, in: machOFile)).print(using: DemangleOptions.default)
            for record in associatedType.records where try record.name(in: machOFile) == "B" {
                let node = try SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machOFile), in: machOFile)
                texts[conformer] = await node.resolveOpaqueTypeCollectingConditionalCandidates(in: machOFile, spelling: spelling).node.print(using: DemangleOptions.default)
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

    /// Without a search path that reaches `ProbeCore` the reference is not
    /// expanded — and it is spelled the one way Swift has for naming an
    /// opaque archetype of another declaration, the textual-interface
    /// attribute. Never the conformer, never a guess, and no longer the
    /// demangler's `<<opaque return type of …>>.0`, which no compiler
    /// accepts.
    @Test func withoutTheImageTheReferenceIsSpelledAsTheCompilerSpellsIt() async throws {
        let (client, _) = try loadClient()
        let texts = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try await resolvedWitnessTexts(in: client)
        }
        #expect(texts["ProbeClient.Outer"] == Self.helperReferenceForOuter, "\(String(describing: texts["ProbeClient.Outer"]))")
        #expect(texts["ProbeClient.Composite"] == Self.helperReferenceForComposite, "\(String(describing: texts["ProbeClient.Composite"]))")
    }

    /// The dump's spelling adds what a reader wants and a compiler does not
    /// need: the declaration the opaque type belongs to, as a comment after
    /// the attribute.
    @Test func withoutTheImageTheAnnotatedSpellingNamesTheOwnerDeclaration() async throws {
        let (client, _) = try loadClient()
        let texts = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try await resolvedWitnessTexts(in: client, spelling: .annotated)
        }
        let expected = Self.helperReferenceForOuter + " /* (extension in ProbeCore):ProbeCore.HasBody.helper() -> some */"
        #expect(texts["ProbeClient.Outer"] == expected, "\(String(describing: texts["ProbeClient.Outer"]))")
    }

    /// The interface path degrades the same way the dump path does.
    ///
    /// The fourth corner of this suite's grid, and the one that was missing:
    /// dump±search-path and interface+search-path were all covered, so nothing
    /// watched what the interface printed when the reference could NOT be
    /// expanded. It printed the conformer — `typealias B = ProbeClient.Outer`,
    /// a real, fully-qualified, wrong type — because `printOpaqueType` printed
    /// the node's generic argument list instead of the reference. Unexpandable
    /// must read as unexpandable on both paths, spelled identically.
    @Test func withoutTheImageTheInterfaceSpellsTheReferenceLikeTheCompiler() async throws {
        let (client, _) = try loadClient()
        let interface = try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: client)
            try await builder.prepare()
            return try await builder.printRoot().string
        }
        #expect(interface.contains("typealias B = " + Self.helperReferenceForOuter + "\n"), "\(interface)")
        #expect(interface.contains("typealias B = " + Self.helperReferenceForComposite + "\n"), "\(interface)")
        #expect(!interface.contains("typealias B = ProbeClient."), "\(interface)")
        #expect(!interface.contains("opaque return type of"), "\(interface)")
    }
}
