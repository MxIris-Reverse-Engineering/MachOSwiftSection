import Foundation
import Testing
import MachOKit
import MachOKitExtensions
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
    /// The fixture's working directory must outlive every test in the
    /// (serialized) suite, so it is removed at process exit rather than per
    /// test. A crashed run still leaks one directory; the unique name keeps
    /// that harmless and non-colliding across parallel test processes.
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

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LegacyDyldInfoBindFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

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
            // Drain BEFORE waitUntilExit: diagnostics beyond the ~64 KB pipe
            // buffer would otherwise deadlock compiler and parent (the child
            // blocked writing, the parent parked waiting) — and because this
            // is a static let under a serialized suite, that deadlock would
            // hang the whole test run instead of reporting a failure.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let diagnostics = String(decoding: diagnosticsData, as: UTF8.self)
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

    /// Walks the fixture's `LC_DYLD_INFO` opcode stream (via MachOKit's
    /// public decoding) just far enough to compute the first bound slot's
    /// file offset — the same segment-base + segment-offset arithmetic the
    /// production index applies.
    private func firstLegacyBindSlotFileOffset(in machOFile: MachOFile) -> Int? {
        guard let bindOperations = machOFile.bindOperations else { return nil }
        let segmentFileOffsets = machOFile.segments.map { UInt64($0.fileOffset) }
        var segmentIndex = 0
        var segmentOffset: UInt = 0
        for operation in bindOperations {
            switch operation {
            case .set_segment_and_offset_uleb(let segment, let offset):
                segmentIndex = Int(segment)
                segmentOffset = offset
            case .add_addr_uleb(let offset):
                segmentOffset &+= offset
            case .do_bind, .do_bind_add_addr_uleb, .do_bind_add_addr_imm_scaled, .do_bind_uleb_times_skipping_uleb:
                guard segmentFileOffsets.indices.contains(segmentIndex) else { return nil }
                return Int(segmentFileOffsets[segmentIndex] &+ UInt64(segmentOffset))
            default:
                continue
            }
        }
        return nil
    }

    /// `isBind(fileOffset:)` and `resolveBind(fileOffset:)` must give the
    /// same answer for the same slot: a consumer that gates a bind read on
    /// `isBind` would otherwise get nothing on exactly the legacy binaries
    /// the opcode-stream fallback was added for.
    @Test func isBindAgreesWithResolveBindOnLegacyBinaries() throws {
        let machOFile = try loadFixtureMachOFile()
        let bindSlotFileOffset = try #require(firstLegacyBindSlotFileOffset(in: machOFile))
        #expect(machOFile.resolveBind(fileOffset: bindSlotFileOffset) != nil)
        #expect(machOFile.isBind(fileOffset: bindSlotFileOffset))
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
