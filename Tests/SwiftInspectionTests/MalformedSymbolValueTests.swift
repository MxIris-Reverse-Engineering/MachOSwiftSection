import Foundation
import Testing
import MachOKit
import Demangling
@_spi(Internals) import MachOSymbols
@testable @_spi(Internals) import SwiftInspection

/// A symbol's value is the binary's own claim about where something sits, and
/// two indexes read the bytes there: `SymbolicManglingIndex` (the mangled name
/// a symbolic-mangling symbol names) and `ObjCImplementationClassIndex` (the
/// offset a direct field offset global holds). A malformed binary can claim a
/// value that is no offset at all: an `n_value` of 2^63 or more in a
/// standalone file comes back from MachOKit as a negative offset, and the file
/// reader converts every offset to `UInt64` before any bounds check — a trap
/// that no `try?` catches. The binary under analysis must not decide whether
/// the host process lives (the same rule that makes `PackedNameReference`
/// failable on a name's binary-supplied geometry), so such a symbol is skipped
/// and never read.
///
/// The fixture is a real linked dylib. Assembler `.set`s make the malformed
/// symbols absolute local symbols, which the linker keeps. `FixtureAnchor`
/// gives the compiler a well-formed symbolic-mangling symbol to emit beside
/// them and puts a class in `__objc_classlist`; it is also the ballast every
/// compiled-on-the-fly fixture needs (a struct-only dylib has no `__DATA`
/// segment, whose chained-fixup pages MachOKit before 0.52.103 mis-walked).
@Suite(.serialized)
struct MalformedSymbolValueTests {
    private static let malformedSymbolicManglingSymbolName = "_symbolic _____ 4Main3FooV"

    /// `direct field offset for (extension in Probe):__C.NSObject.value : Swift.Int`
    /// — the shape `ObjCImplementationClassIndex` reads a stored property of an
    /// `@objc @implementation` class from.
    private static let malformedFieldOffsetSymbolName = "_$sSo8NSObjectC5ProbeE5valueSivpWvd"

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
        var description: String { "malformed symbol value fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MalformedSymbolValueFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let swiftSourceURL = workingDirectory.appendingPathComponent("Anchor.swift")
            try "public final class FixtureAnchor {}\n".write(to: swiftSourceURL, atomically: true, encoding: .utf8)
            let assemblySourceURL = workingDirectory.appendingPathComponent("MalformedSymbols.s")
            try """
                .section __TEXT,__const
                .set "\(malformedSymbolicManglingSymbolName)", 0x8000000000000010
                .set "\(malformedFieldOffsetSymbolName)", 0x8000000000000020

            """.write(to: assemblySourceURL, atomically: true, encoding: .utf8)
            let objectURL = workingDirectory.appendingPathComponent("MalformedSymbols.o")
            let libraryURL = workingDirectory.appendingPathComponent("libProbeMalformedSymbolValue.dylib")
            try run(tool: "clang", arguments: [
                "-target", "arm64-apple-macosx15.0",
                "-c", assemblySourceURL.path, "-o", objectURL.path,
            ])
            try run(tool: "swiftc", arguments: [
                "-emit-library", "-module-name", "ProbeMalformedSymbolValue",
                "-target", "arm64-apple-macosx15.0",
                swiftSourceURL.path, objectURL.path, "-o", libraryURL.path,
            ])
            return libraryURL
        }
    }()

    private static func run(tool: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [tool] + arguments
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

    private static func fixtureFile() throws -> MachOFile {
        let libraryURL = try fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    @Test("a symbolic-mangling symbol whose value is no offset is counted unpaired instead of read")
    func symbolicManglingSymbolWhoseValueIsNoOffsetIsSkipped() throws {
        let machOFile = try Self.fixtureFile()
        // Read through the symbol store, which collects the symbol without
        // reading what it points at — asking the index would build it.
        let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOFile))
        let malformedPosition = try #require(collectedSymbols.position(ofSymbolNamed: Self.malformedSymbolicManglingSymbolName), "the premise: the linker kept the malformed symbol")
        try #require(collectedSymbols[malformedPosition].offset < 0, "the premise: MachOKit hands the value back as a negative offset")

        #expect(SymbolicManglingIndex.shared.unpairedSymbolCount(in: machOFile) == 1)
        // The well-formed symbol next to it still pairs.
        let referentNames = SymbolicManglingIndex.shared.references(in: machOFile).compactMap { reference in
            SymbolicManglingIndex.shared.referentNode(of: reference, in: machOFile)?.print(using: .default)
        }
        #expect(referentNames.contains("ProbeMalformedSymbolValue.FixtureAnchor"), "\(referentNames)")
    }

    @Test("a field offset global whose value is no offset is never read")
    func fieldOffsetSymbolWhoseValueIsNoOffsetIsSkipped() throws {
        let machOFile = try Self.fixtureFile()
        let malformedSymbol = try #require(
            SymbolIndexStore.shared.symbols(of: .fieldOffset, in: machOFile).first { $0.symbol.name == Self.malformedFieldOffsetSymbolName },
            "the premise: the symbol index demangles the malformed field offset symbol"
        )
        try #require(malformedSymbol.offset < 0, "the premise: MachOKit hands the value back as a negative offset")
        try #require(machOFile.objcImplementationClassObjects() != nil, "the premise: the image has a class list, so the index scans its field offset symbols")

        // `FixtureAnchor` is a Swift class, so nothing is recognized; what is
        // under test is that building the index reaches that answer at all.
        #expect(ObjCImplementationClasses.all(in: machOFile).isEmpty)
    }
}
