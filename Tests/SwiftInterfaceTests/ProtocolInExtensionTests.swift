import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface

/// A protocol declared inside an extension (SE-0404) — `extension Host {
/// protocol Delegate {…} }` — has no parent type definition, only an
/// extension context, so the printer took it for a top-level protocol and
/// printed its default-implementation extensions right after it: inside the
/// enclosing extension's braces, at column 0. Swift cannot nest an extension
/// there (Foundation's interface read `extension __C.NSNotificationCenter {
/// protocol AsyncMessage {…} extension …AsyncMessage {…} }`), and a host
/// could not take the protocol out of the extension's print (evolution
/// proposal `nested-definition-regions`): those trailing lines were not
/// indented by the nesting. They now print in the interface's top-level
/// extensions block, like the extensions of a protocol nested in a type.
@Suite(.serialized)
struct ProtocolInExtensionTests {
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

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "protocol-in-extension fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProtocolInExtensionFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("ProtocolsInExtensions.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeProtocolInExtension.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeProtocolInExtension",
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ])
            return libraryURL
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

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    ///
    /// Only `Int.Counter` has an extension context. The compiler parents a
    /// protocol declared in an extension of this module's own type on the
    /// type itself, so `Host.Delegate` is a nested protocol of `Host` — the
    /// case that already printed right, kept here as the contrast.
    private static let source = """
    public final class FixtureAnchor {}

    public struct Host {
        public init() {}
    }

    extension Host {
        public protocol Delegate {
            func handle()
        }
    }

    extension Host.Delegate {
        public func handle() {}
        public func delegateHelper() -> Int { 0 }
    }

    extension Int {
        public protocol Counter {
            var count: Int { get }
        }
    }

    extension Int.Counter {
        public var count: Int { 0 }
        public func counterHelper() -> Int { 1 }
    }
    """

    private func loadFixture() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            return file
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// The lines starting an `extension` while inside another declaration's
    /// braces.
    private static func extensionsOpenedInsideBraces(of interface: String) -> [String] {
        var depth = 0
        var nestedExtensionLines: [String] = []
        for line in interface.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if depth > 0, trimmed.hasPrefix("extension ") {
                nestedExtensionLines.append(String(line))
            }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        }
        return nestedExtensionLines
    }

    @Test("the default implementations of a protocol declared in an extension print in the top-level extensions block")
    func defaultImplementationsPrintAtTheTopLevel() async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: try loadFixture())
        try await builder.prepare()
        let interface = try await builder.printRoot().string

        #expect(Self.extensionsOpenedInsideBraces(of: interface).isEmpty, "\(interface)")
        let topLevelExtensionLines = interface.split(separator: "\n").filter { $0.hasPrefix("extension ") }
        #expect(topLevelExtensionLines.contains { $0.contains("Host.Delegate") }, "\(interface)")
        #expect(topLevelExtensionLines.contains { $0.contains("Int.Counter") }, "\(interface)")
        // Printed once, not dropped and not repeated.
        #expect(interface.components(separatedBy: "func delegateHelper()").count == 2, "\(interface)")
        #expect(interface.components(separatedBy: "func counterHelper()").count == 2, "\(interface)")
    }

    @Test("a protocol declared in an extension prints on its own without its default-implementation extensions")
    func standalonePrintCarriesNoExtension() async throws {
        let machOFile = try loadFixture()
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        let printer = SwiftDeclarationPrinter(configuration: .init(), in: machOFile)

        #expect(indexer.allProtocolDefinitions.values.filter { $0.extensionContext != nil }.count == 1)
        let nestedProtocols = indexer.allProtocolDefinitions.values.filter { $0.parent != nil || $0.extensionContext != nil }
        #expect(nestedProtocols.count == 2)
        for protocolDefinition in nestedProtocols {
            let printed = try await printer.printProtocolDefinition(protocolDefinition).string
            #expect(!printed.contains("extension"), "\(printed)")
        }
    }

    @Test("a protocol declared in an extension, taken out of the extension's print, is its own print")
    func regionTakenOutOfTheExtensionIsTheProtocolsOwnPrint() async throws {
        let machOFile = try loadFixture()
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.marksNestedDefinitions = true
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)

        let extensionsDeclaringProtocols = indexer.typeExtensionDefinitions.values.flatMap { $0 }.filter { !$0.protocols.isEmpty }
        #expect(extensionsDeclaringProtocols.count == 1)
        for extensionDefinition in extensionsDeclaringProtocols {
            let printed = try await printer.printExtensionDefinition(extensionDefinition).frozen()
            let regions = printed.separatingDefinitionRegions().definitions.regions
            let protocolDefinition = try #require(extensionDefinition.protocols.first)
            let region = try #require(regions.first, "\(printed.string)")
            let expectedIdentity = try await mangleAsString(protocolDefinition.protocolName.node)
            #expect(region.identity == expectedIdentity)

            let takenOut = printed.content(ofDefinitionRegion: region).removingIndentation(levels: region.depth + 1)
            let ownPrint = try await printer.printProtocolDefinition(protocolDefinition).frozen()
            #expect(takenOut == ownPrint, "\(printed.string)")
        }
    }
}
