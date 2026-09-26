import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing

/// A type declared inside `extension <C-imported type> { … }` is filed under a
/// synthetic extension of that C type, keyed by an `ExtensionName` whose
/// `kind` a host such as RuntimeViewer uses to group the extension ("Swift
/// Class Extension" versus "Swift Struct Extension").
///
/// Since evolution proposal `type-import-info-identity` a C typedef the
/// importer promoted to a nominal type demangles as a `typeAlias`, and a walk
/// over that tree cannot tell a CF class (`__C.ProbeObjectRef`, one object
/// reference) from a typedef struct (`__C.ProbeRecord`): `Node.typeKind`
/// answers `.struct` for both. The extended context's own descriptor knows,
/// so the indexer asks it for exactly this shape. Before that a CF class's
/// extension moved from the class group to the struct group when its name
/// changed from `__C.Subgraph` to `__C.AGSubgraphRef`.
@Suite
struct CImportedExtensionKindTests {
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

    /// `ProbeObjectRef` is a CF-bridged class (the importer names it
    /// `ProbeObject`, the compiler spells it `So14ProbeObjectRefa`);
    /// `ProbeRecord` is a typedef of an anonymous struct, which mangles the
    /// same way (`So11ProbeRecorda`). Both descriptors are foreign and are
    /// emitted into the fixture image itself, so the extended context of an
    /// extension on either is a direct symbolic reference.
    private static let fixtureHeader = """
    #import <Foundation/Foundation.h>

    typedef struct CF_BRIDGED_TYPE(id) ProbeObjectStorage *ProbeObjectRef;

    typedef struct { int value; } ProbeRecord;
    """

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class").
    private static let fixtureSource = """
    import Foundation

    public final class Anchor {}

    extension ProbeObject {
        public struct Nested {
            public var value: Int
            public init(value: Int) { self.value = value }
        }
    }

    extension ProbeRecord {
        public struct Nested {
            public var value: Int
            public init(value: Int) { self.value = value }
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CImportedExtensionKindFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let headerURL = workingDirectory.appendingPathComponent("CImportedExtensionKindFixture.h")
            let sourceURL = workingDirectory.appendingPathComponent("CImportedExtensionKindFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libCImportedExtensionKindFixture.dylib")
            try fixtureHeader.write(to: headerURL, atomically: true, encoding: .utf8)
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "CImportedExtensionKindFixture",
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
        var description: String { "C-imported-extension-kind fixture compilation failed:\n\(diagnostics)" }
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

    private func typeExtensionKind(of extendedTypeName: String) async throws -> ExtensionKind {
        let machOFile = try loadFixtureMachOFile()
        let indexer = SwiftDeclarationIndexer(configuration: .init(showCImportedTypes: false), eventHandlers: [], in: machOFile)
        try await indexer.prepare()
        let match = indexer.typeExtensionDefinitions.first { $0.key.name == extendedTypeName }
        let (extensionName, definitions) = try #require(match, Comment(rawValue: "no type extension of \(extendedTypeName) was indexed; extensions found: \(indexer.typeExtensionDefinitions.keys.map { $0.name })"))
        let nestedTypeNames = definitions.flatMap { $0.types }.map { $0.typeName.name }
        #expect(nestedTypeNames == ["\(extendedTypeName).Nested"], Comment(rawValue: "the extension of \(extendedTypeName) should carry exactly the nested type declared in it"))
        return extensionName.kind
    }

    @Test
    func extensionOfCFClassIsFiledAsClass() async throws {
        #expect(try await typeExtensionKind(of: "__C.ProbeObjectRef") == .type(.class))
    }

    @Test
    func extensionOfCTypedefStructIsFiledAsStruct() async throws {
        #expect(try await typeExtensionKind(of: "__C.ProbeRecord") == .type(.struct))
    }
}
