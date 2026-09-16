import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface

/// `@_rawLayout` is an experimental feature any module can enable, not a
/// standard-library privilege, and only its `like:` spelling leaves a field
/// record. `size:alignment:` and a non-generic `likeArrayOf:count:` leave
/// just the `__swift5_builtin` descriptor every fixed-size raw-layout struct
/// gets; the interface recovers `@_rawLayout(size:alignment:)` from it and
/// says so, since the two spellings are recorded identically. A generic
/// `likeArrayOf:` struct leaves nothing and prints no attribute, and an
/// `@_alignment` empty struct — which also gets a builtin descriptor — must
/// not be mistaken for one.
///
/// One module compiled on the fly with the feature enabled (it carries a
/// class: a struct-only fixture dylib has no `__DATA` segment and the pinned
/// MachOKit mis-walks its chained-fixup pages). Whichever toolchain compiles
/// it — the builtin descriptor predates Swift 6.4, the artificial `like:`
/// record does not — the assertions hold; see the last test.
@Suite(.serialized)
struct RawLayoutBuiltinDescriptorRenderingTests {
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
        var description: String { "raw-layout fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RawLayoutRenderingFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("RawLayouts.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeRawLayout.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeRawLayout",
                "-enable-experimental-feature", "RawLayout",
                // Value generics (`let count: Int`) need macOS 26.
                "-target", "arm64-apple-macosx26.0",
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

    private static let source = """
    public final class ProbeAnchor {}

    @_rawLayout(size: 12, alignment: 4)
    public struct OpaqueTwelve: ~Copyable {
        public init() {}
    }

    @_rawLayout(likeArrayOf: UInt32, count: 4)
    public struct QuadWords: ~Copyable {
        public init() {}
    }

    @_rawLayout(likeArrayOf: Element, count: count)
    public struct Buffer<Element: ~Copyable, let count: Int>: ~Copyable {
        public init() {}
    }

    @_rawLayout(like: Int)
    public struct LikeInt: ~Copyable {
        public init() {}
    }

    @_alignment(16)
    public struct AlignedEmpty {
        public init() {}
    }

    public struct Plain {
        public var value: Int = 0
        public init() {}
    }
    """

    private func renderInterface() async throws -> String {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The line printed directly above `declaration`, or `nil` when the
    /// declaration is not in the interface.
    private func lineAbove(_ declaration: String, in interface: String) -> String? {
        let lines = interface.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix(declaration) }), index > 0 else { return nil }
        return lines[index - 1]
    }

    private static let builtinStorageComment = "// size and alignment from the builtin type descriptor; the source may spell this as likeArrayOf:count:"

    @Test func aSizeAndAlignmentStructPrintsTheRecordedLayoutAsItsAttribute() async throws {
        let interface = try await renderInterface()
        #expect(lineAbove("struct OpaqueTwelve", in: interface) == "@_rawLayout(size: 12, alignment: 4) \(Self.builtinStorageComment)", "\(interface)")
        // Nothing renders as a stored property.
        #expect(interface.contains("struct OpaqueTwelve: ~Swift.Copyable {\n    init()\n}"), "\(interface)")
    }

    @Test func aFixedArrayLikeStructPrintsItsSizeAndAlignmentBecauseThatIsAllTheBinaryRecords() async throws {
        let interface = try await renderInterface()
        #expect(lineAbove("struct QuadWords", in: interface) == "@_rawLayout(size: 16, alignment: 4) \(Self.builtinStorageComment)", "\(interface)")
    }

    @Test func aGenericArrayLikeStructAndAnAlignedEmptyStructPrintNoAttribute() async throws {
        let interface = try await renderInterface()
        let bufferAttributeLine = try #require(lineAbove("struct Buffer<", in: interface), "\(interface)")
        #expect(!bufferAttributeLine.hasPrefix("@_rawLayout"), "\(interface)")
        let alignedAttributeLine = try #require(lineAbove("struct AlignedEmpty", in: interface), "\(interface)")
        #expect(!alignedAttributeLine.hasPrefix("@_rawLayout"), "\(interface)")
        let plainAttributeLine = try #require(lineAbove("struct Plain", in: interface), "\(interface)")
        #expect(!plainAttributeLine.hasPrefix("@_rawLayout"), "\(interface)")
    }

    /// A non-generic `like:` struct carries both facts: the artificial field
    /// record (Swift 6.4 compilers) and the builtin descriptor (every
    /// compiler). The record wins when present; the descriptor is the
    /// fallback — so exactly one of the two spellings renders, whichever
    /// toolchain compiled the fixture.
    @Test func theLikeSpellingWinsOverTheBuiltinDescriptorWhenTheRecordExists() async throws {
        let interface = try await renderInterface()
        let likeIntAttributeLine = try #require(lineAbove("struct LikeInt", in: interface), "\(interface)")
        let likeSpelling = "@_rawLayout(like: Swift.Int)"
        let descriptorSpelling = "@_rawLayout(size: 8, alignment: 8) \(Self.builtinStorageComment)"
        #expect(likeIntAttributeLine == likeSpelling || likeIntAttributeLine == descriptorSpelling, "\(interface)")
        #expect(!interface.contains("_rawLayout:"), "the artificial record must not render as a stored property")
    }
}
