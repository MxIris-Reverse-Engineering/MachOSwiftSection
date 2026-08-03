import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// Regression tests for binaries carrying the legacy `LC_DYLD_INFO(_ONLY)`
/// opcode-based fixups (deployment target < macOS 12 / iOS 16, e.g. every
/// iOS 15.5 simulator framework).
///
/// Two independent defects used to compound on such binaries:
/// 1. `resolveBind(fileOffset:)` only understood `LC_DYLD_CHAINED_FIXUPS`,
///    so every indirect reference to another image's descriptor (external
///    protocol conformances, external superclasses) read as a garbage
///    pointer (`FileIOError.offsetOutOfBounds` / `invalidContextDescriptor`).
/// 2. `SwiftInterfaceBuilder.printRoot` caught errors per BLOCK, so the first
///    type whose printing threw blanked every type in the interface.
///
/// The fixture is compiled on the fly with a pre-chained-fixups deployment
/// target, which the linker answers with `LC_DYLD_INFO_ONLY` — the same
/// format as the iOS 15.5 simulator frameworks that surfaced the bug.
@Suite(.serialized)
struct LegacyDyldInfoBindTests {
    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LegacyDyldInfoBindFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

            let sourceURL = workingDirectory.appendingPathComponent("LegacyFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libLegacyFixture.dylib")
            try Self.fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            // macOS 11 predates chained fixups, forcing LC_DYLD_INFO_ONLY output.
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "LegacyFixture",
                "-target", "arm64-apple-macosx11.0",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let diagnostics = String(decoding: standardErrorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                throw LegacyFixtureCompilationError(diagnostics: diagnostics)
            }
            return libraryURL
        }
    }()

    private struct LegacyFixtureCompilationError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "Legacy fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureSource = """
    import Foundation

    public struct LegacyPoint: Equatable, Hashable, Codable {
        public var x: Int
        public var y: Int
    }

    public enum LegacyState: Int, CaseIterable {
        case idle
        case running
    }

    public class LegacyDecoder: JSONDecoder, @unchecked Sendable {
        public var callCount: Int = 0
    }

    public protocol LegacyGreeting {
        func greet() -> String
    }

    public struct LegacyGreeter: LegacyGreeting {
        public func greet() -> String { "hello" }
    }
    """

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

    private func buildInterfaceOutput(of machOFile: MachOFile) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    @Test func fixtureUsesLegacyDyldInfoFixups() throws {
        let machOFile = try loadFixtureMachOFile()
        #expect(machOFile.dyldChainedFixups == nil)
        #expect(machOFile.bindOperations != nil)
    }

    /// Pins the opcode-bind fallback: conformances to protocols living in
    /// OTHER images (Equatable/Hashable/CaseIterable in libswiftCore) resolve
    /// only when the bind slot's target symbol is recovered from the
    /// `LC_DYLD_INFO` opcode stream. Before the fix 13 of the fixture's 14
    /// conformances failed with `offsetOutOfBounds` and none of these
    /// extensions rendered.
    @Test func externalProtocolConformancesResolveOnLegacyBinaries() async throws {
        let machOFile = try loadFixtureMachOFile()
        let interfaceOutput = try await buildInterfaceOutput(of: machOFile)
        #expect(interfaceOutput.contains("extension LegacyFixture.LegacyPoint: Swift.Equatable"))
        #expect(interfaceOutput.contains("extension LegacyFixture.LegacyPoint: Swift.Hashable"))
        #expect(interfaceOutput.contains("extension LegacyFixture.LegacyState: Swift.CaseIterable"))
    }

    /// Pins per-item print degradation end to end: every fixture type must
    /// appear in the interface. Before the batch the first type whose
    /// printing threw (the external-superclass class) blanked the WHOLE
    /// types block, leaving only imports and global declarations.
    @Test func interfaceContainsEveryTypeOnLegacyBinaries() async throws {
        let machOFile = try loadFixtureMachOFile()
        let interfaceOutput = try await buildInterfaceOutput(of: machOFile)
        #expect(interfaceOutput.contains("struct LegacyPoint"))
        #expect(interfaceOutput.contains("enum LegacyState"))
        #expect(interfaceOutput.contains("class LegacyDecoder"))
        #expect(interfaceOutput.contains("struct LegacyGreeter"))
        #expect(interfaceOutput.contains("protocol LegacyGreeting"))
    }
}
