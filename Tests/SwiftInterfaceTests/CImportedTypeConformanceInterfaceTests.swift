import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface

/// Evolution proposal `type-import-info-identity`: the conformance extensions
/// the importer synthesizes for C-imported types render as ONE block per
/// conformance, carrying both the associated-type witness (`typealias
/// RawValue`) and the witness members (`init?(rawValue:)`, `rawValue`).
///
/// Three producers name the same type — the conformance descriptor (through
/// its type reference), the `__swift5_assocty` record (through its mangled
/// conforming-type name) and the witness symbols — and they only join when
/// their `TypeName`s agree. Before the import-info rules a C tag enum was
/// spelled `enum` by the descriptor and `structure` by the symbols, so the
/// members never joined; with the rules the descriptor also says `structure`,
/// and the name's `kind` must not split the join again (the descriptor still
/// says `enum` there). A `swift_wrapper` typedef is the other shape: its
/// mangling is a `typeAlias`, which no `TypeKind` used to describe, so its
/// associated-type record was dropped outright.
@Suite
struct CImportedTypeConformanceInterfaceTests {
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

    private static let fixtureHeader = """
    #import <Foundation/Foundation.h>

    typedef NS_ENUM(NSInteger, ProbeMode) { ProbeModeOne, ProbeModeTwo };

    typedef NSString *ProbeIdentifier __attribute__((swift_wrapper(struct)));
    """

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class"). The importer's
    /// synthesized conformances are emitted on demand: only passing the
    /// values through generic functions that require `RawRepresentable` and
    /// `Hashable` puts their conformance descriptors, witness tables and
    /// associated-type records into this image.
    private static let fixtureSource = """
    import Foundation

    public final class Anchor {}

    public struct Holder {
        public var mode: ProbeMode
        public var identifier: ProbeIdentifier

        public init(mode: ProbeMode, identifier: ProbeIdentifier) {
            self.mode = mode
            self.identifier = identifier
        }
    }

    @inline(never) public func rawValue<Value: RawRepresentable>(of value: Value) -> Value.RawValue { value.rawValue }
    @inline(never) public func hashValue<Value: Hashable>(of value: Value) -> Int { value.hashValue }

    public func exerciseConformances(_ holder: Holder) -> (Int, String, Int, Int) {
        (rawValue(of: holder.mode), rawValue(of: holder.identifier), hashValue(of: holder.mode), hashValue(of: holder.identifier))
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CImportedTypeConformanceFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let headerURL = workingDirectory.appendingPathComponent("CImportedTypeConformanceFixture.h")
            let sourceURL = workingDirectory.appendingPathComponent("CImportedTypeConformanceFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libCImportedTypeConformanceFixture.dylib")
            try fixtureHeader.write(to: headerURL, atomically: true, encoding: .utf8)
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "CImportedTypeConformanceFixture",
                "-target", "arm64-apple-macosx15.0",
                "-import-objc-header", headerURL.path,
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "C-imported-type-conformance fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    private func buildInterface() async throws -> String {
        let machOFile = try loadFixtureMachOFile()
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(printConfiguration: SwiftDeclarationPrintConfiguration()),
            eventHandlers: [],
            in: machOFile
        )
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The bodies of every `extension <typeName>: … Swift.RawRepresentable …`
    /// block in the interface, one string per block.
    private func rawRepresentableBlockBodies(of typeName: String, in interface: String) -> [String] {
        var bodies: [String] = []
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("extension \(typeName): "), line.contains("Swift.RawRepresentable") {
                if line.hasSuffix("{}") {
                    // An emptied conformance block: the members never joined.
                    bodies.append("")
                } else if line.hasSuffix("{") {
                    var body: [String] = []
                    index += 1
                    while index < lines.count, !lines[index].hasPrefix("}") {
                        body.append(lines[index])
                        index += 1
                    }
                    bodies.append(body.joined(separator: "\n"))
                }
            }
            index += 1
        }
        return bodies
    }

    @Test(arguments: [
        // A C tag enum: descriptor kind `enum`, mangled as a structure.
        ("__C.ProbeMode", "typealias RawValue = Swift.Int"),
        // A `swift_wrapper` typedef: mangled as a `typeAlias`.
        ("__C.ProbeIdentifier", "typealias RawValue = Swift.String"),
    ])
    func rawRepresentableConformanceRendersWitnessAndMembersInOneBlock(typeName: String, witnessLine: String) async throws {
        let interface = try await buildInterface()
        let bodies = rawRepresentableBlockBodies(of: typeName, in: interface)
        #expect(bodies.count == 1, "expected exactly one RawRepresentable block for \(typeName), found \(bodies.count)")
        let body = try #require(bodies.first, Comment(rawValue: "no RawRepresentable block for \(typeName)"))
        #expect(body.contains(witnessLine), Comment(rawValue: "\(typeName): associated-type witness missing from the block:\n\(body)"))
        #expect(body.contains("init?(rawValue: Self.RawValue)"), Comment(rawValue: "\(typeName): witness members missing from the block:\n\(body)"))
        // The witness must not ALSO surface as a bare `extension X { typealias … }`.
        #expect(!interface.contains("extension \(typeName) {\n    \(witnessLine)"), Comment(rawValue: "\(typeName): the witness split into a bare extension block"))
    }
}
