import Foundation
import Testing
import MachOKit
import Semantic
@_spi(Internals) @testable import MachOSymbols
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface

/// The exported-only filter (evolution proposal
/// `exported-only-interface`) over `internal` declarations — the
/// shape `SymbolTestsCore` cannot pin, because that fixture is built with
/// `ENABLE_TESTABILITY` and exports its internals. This module is compiled
/// on the fly with `-enable-library-evolution` and WITHOUT `-enable-testing`,
/// so every `internal` declaration is a local symbol and the filter has a
/// definitive negative to act on for: a type, a nested type, a protocol and
/// its default implementation, a method, a stored property, a global, a
/// conformance to an internal protocol, and a constrained extension whose
/// members are all internal.
@Suite(.serialized)
struct ExportedOnlyLibraryEvolutionFixtureTests {
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

    /// The `Anchor` class is load-bearing fixture ballast: a struct-only
    /// module compiles to a dylib with no `__DATA` segment, whose
    /// chained-fixup pages the pinned MachOKit release mis-walks (see
    /// `DiffMemberIndentationTests`). `@inline(never)` keeps the internal
    /// members' symbols from being folded away.
    private static let fixtureSource = """
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
    """

    // `Swift.Error` spelled out: the `Semantic` import brings its own `Error`
    // type into scope, which would otherwise win the lookup.
    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExportedOnlyFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("ExportedOnlyFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libExportedOnlyFixture.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-enable-library-evolution",
                "-module-name", "ExportedOnlyFixture",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let diagnostics = String(decoding: diagnosticsData, as: UTF8.self)
                throw FixtureCompilationError(diagnostics: diagnostics)
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "Exported-only fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let file = try MachOKit.loadFromFile(url: libraryURL)
        switch file {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    private func buildOutput(exportedOnly: Bool) async throws -> (output: String, machOFile: MachOFile) {
        let machOFile = try loadFixtureMachOFile()
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printExportedDeclarationsOnly = exportedOnly
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(printConfiguration: printConfiguration),
            eventHandlers: [],
            in: machOFile
        )
        try await builder.prepare()
        return (try await builder.printRoot().string, machOFile)
    }

    /// The premise every assertion below rests on: without `-enable-testing`
    /// the internal descriptors are local symbols and the public ones are
    /// in the trie — the store must answer `false` / `true`, never `nil`.
    @Test func fixtureExportsExactlyItsPublicDescriptors() async throws {
        let (_, machOFile) = try await buildOutput(exportedOnly: false)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture11PublicShapeVMn", in: machOFile) == true)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture13InternalShapeVMn", in: machOFile) == false)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture14PublicContractMp", in: machOFile) == true)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture16InternalContractMp", in: machOFile) == false)
    }

    @Test func internalTypesAreDroppedAtEveryNestingLevel() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("struct InternalShape {"))
        #expect(defaultOutput.contains("struct InternalNested {"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("struct PublicShape {"))
        #expect(filteredOutput.contains("struct PublicNested {"))
        #expect(!filteredOutput.contains("struct InternalShape {"))
        #expect(!filteredOutput.contains("struct InternalNested {"))
        // The internal type's extension goes with its target.
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.InternalShape"))
        #expect(!filteredOutput.contains("orphanMethod"))
    }

    @Test func internalProtocolItsDefaultsAndConformancesToItAreDropped() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("protocol InternalContract {"))
        #expect(defaultOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.InternalContract"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("protocol PublicContract {"))
        #expect(filteredOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.PublicContract"))
        #expect(filteredOutput.contains("func requirement()"))
        #expect(!filteredOutput.contains("protocol InternalContract {"))
        #expect(!filteredOutput.contains("hiddenDefault"))
        // A PUBLIC type's conformance to an INTERNAL protocol: the target is
        // exported, the conforming protocol is not — the extension goes.
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.InternalContract"))
        #expect(!filteredOutput.contains("func hidden()"))
    }

    /// Members and STORED properties of a kept type: the internal method and
    /// the internal stored `var` (whose accessor group joined as local
    /// symbols) go, the public ones stay.
    @Test func internalMembersAndStoredPropertiesAreDropped() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("var internalNote: Swift.String"))
        #expect(defaultOutput.contains("func internalMethod()"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("var title: Swift.String"))
        #expect(filteredOutput.contains("func publicMethod()"))
        #expect(filteredOutput.contains("init(title: Swift.String, internalNote: Swift.String)"))
        #expect(!filteredOutput.contains("var internalNote"))
        #expect(!filteredOutput.contains("func internalMethod()"))
    }

    /// Constrained-extension members render inside ONE plain
    /// `extension Foo { … }` container per type, each member carrying its
    /// own `where` clause. `PublicPair`'s container holds only an internal
    /// member: the filter EMPTIES it and, being a plain extension, the whole
    /// block goes. `PublicBox`'s container keeps its public member and loses
    /// the internal one.
    @Test func emptiedPlainExtensionIsDroppedAndPopulatedOneKept() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("extension ExportedOnlyFixture.PublicPair {"))
        #expect(defaultOutput.contains("func internalOnlyConstrainedMember() where A == Swift.Int"))
        #expect(defaultOutput.contains("func internalConstrainedMember() where A == Swift.Int"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("struct PublicPair<A> {"))
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.PublicPair"))
        #expect(!filteredOutput.contains("internalOnlyConstrainedMember"))
        #expect(filteredOutput.contains("extension ExportedOnlyFixture.PublicBox {"))
        #expect(filteredOutput.contains("func publicConstrainedMember() where A == Swift.String"))
        #expect(!filteredOutput.contains("internalConstrainedMember"))
    }

    /// Globals follow the member rule; enum cases own no symbols and are
    /// never touched.
    @Test func internalGlobalIsDroppedAndEnumCasesAreKept() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("func internalGlobal()"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("func publicGlobal()"))
        #expect(!filteredOutput.contains("func internalGlobal()"))
        #expect(filteredOutput.contains("case alpha"))
        #expect(filteredOutput.contains("case beta"))
    }

    @Test func filteredOutputHasNoBlankLineArtifacts() async throws {
        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains("\n\n\n"))
        #expect(!filteredOutput.contains("{\n}"))
    }
}
