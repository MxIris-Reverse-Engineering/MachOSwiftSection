#if os(macOS)

import Foundation
import MachOKit
import SwiftPrinting
import Testing
@testable import TypeIndexing

/// Supplementary APINotes files (evolution proposal 0009): user-provided
/// mappings for frameworks with no SDK module, and the merge priority that
/// lets them override SDK entries. The library ships no mappings of its own.
@Suite
struct SupplementaryAPINotesTests {
    private static func writeAPINotesFile(yaml apiNotesYAML: String, into directoryURL: URL, named fileName: String) throws -> URL {
        let fileURL = directoryURL.appending(component: fileName)
        try apiNotesYAML.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(component: "SupplementaryAPINotesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// The AttributeGraph-shaped mapping every example in the contribution
    /// guide is written against: both C spellings of each CF-bridged type.
    private static let attributeGraphYAML = """
    Name: AttributeGraph
    Typedefs:
    - Name: AGGraphRef
      SwiftName: Graph
    - Name: AGSubgraphRef
      SwiftName: Subgraph
    Tags:
    - Name: AGGraphStorage
      SwiftName: Graph
    - Name: AGSubgraphStorage
      SwiftName: Subgraph
    """

    /// The end-to-end data flow for a user-supplied AttributeGraph mapping,
    /// in all three mangling shapes a CF-bridged type reaches Swift metadata
    /// as: the typedef name (`AGGraphRef`, a typealias node → `.other`), the
    /// storage/tag name (`AGGraphStorage`, a foreign *class* descriptor the
    /// consuming binary emits → `.objcClass`), and the imported Swift name
    /// itself (`__C.Graph`, a foreign descriptor recording the post-rename
    /// spelling — attribution-only, no rewrite needed or possible).
    @Test
    func userSuppliedMappingsResolveInAllManglingShapes() async throws {
        let directoryURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        _ = try Self.writeAPINotesFile(yaml: Self.attributeGraphYAML, into: directoryURL, named: "AttributeGraph.apinotes")

        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(supplementaryAPINotesFiles: SupplementaryAPINotesLoader.files(atSupplementaryLocations: [directoryURL]))

        #expect(await typeDatabase.moduleName(forTypeName: "AGGraphRef") == "AttributeGraph")
        #expect(await typeDatabase.moduleName(forTypeName: "AGGraphStorage") == "AttributeGraph")
        #expect(await typeDatabase.moduleName(forTypeName: "Graph") == "AttributeGraph")
        #expect(await typeDatabase.moduleName(forTypeName: "Subgraph") == "AttributeGraph")
        #expect(await typeDatabase.swiftName(forCName: "AGGraphRef", category: .other) == "Graph")
        #expect(await typeDatabase.swiftName(forCName: "AGGraphStorage", category: .objcClass) == "Graph")
        #expect(await typeDatabase.swiftName(forCName: "Graph", category: .objcClass) == nil)
        #expect(await typeDatabase.swiftName(forCName: "AGSubgraphRef", category: .other) == "Subgraph")
        #expect(await typeDatabase.swiftName(forCName: "AGSubgraphStorage", category: .objcClass) == "Subgraph")
    }

    /// A `Tags` rename must be visible to a class-category lookup: the
    /// field-metadata shape of a CF-bridged type is a foreign *class* node
    /// spelled with the C tag name, while APINotes files the entry under
    /// `Tags` per C semantics. A class-table entry still wins over a
    /// same-named tag entry, and the protocol table never falls back.
    @Test
    func classCategoryLookupFallsBackToTheValueTypeTable() throws {
        let directoryURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = try Self.writeAPINotesFile(yaml: """
        Name: TestModule
        Classes:
        - Name: TSTSharedName
          SwiftName: ClassSpelling
        Tags:
        - Name: TSTSharedName
          SwiftName: TagSpelling
        - Name: TSTStorage
          SwiftName: Renamed
        Protocols:
        - Name: TSTProtocolOnly
          SwiftName: ProtocolSpelling
        """, into: directoryURL, named: "TestModule.apinotes")
        let index = APINotesIndex(files: [try APINotesFile(path: fileURL.path(percentEncoded: false))])

        #expect(index.swiftName(forCName: "TSTStorage", category: .objcClass)?.name == "Renamed")
        #expect(index.swiftName(forCName: "TSTSharedName", category: .objcClass)?.name == "ClassSpelling")
        #expect(index.swiftName(forCName: "TSTProtocolOnly", category: .objcClass) == nil)
        #expect(index.swiftName(forCName: "TSTProtocolOnly", category: .other) == nil)
    }

    // MARK: - Merge priority

    /// A supplementary entry overrides the SDK APINotes entry for the same C
    /// name — the "hit it, replace it" contract for user-supplied files.
    @Test
    func supplementaryEntriesOverrideSDKAPINotesEntries() async throws {
        let directoryURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let sdkFileURL = try Self.writeAPINotesFile(yaml: """
        Name: SDKModule
        Typedefs:
        - Name: TSTThingRef
          SwiftName: SDKSpelling
        """, into: directoryURL, named: "SDKModule.apinotes")
        let supplementaryFileURL = try Self.writeAPINotesFile(yaml: """
        Name: CommunityModule
        Typedefs:
        - Name: TSTThingRef
          SwiftName: CommunitySpelling
        """, into: directoryURL, named: "CommunityModule.apinotes")

        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(apiNotesIndex: APINotesIndex(files: [try APINotesFile(path: sdkFileURL.path(percentEncoded: false))]))
        await typeDatabase.register(supplementaryAPINotesFiles: [try APINotesFile(path: supplementaryFileURL.path(percentEncoded: false))])

        #expect(await typeDatabase.swiftName(forCName: "TSTThingRef", category: .other) == "CommunitySpelling")
        #expect(await typeDatabase.moduleName(forTypeName: "TSTThingRef") == "CommunityModule")
    }

    /// Within one supplementary registration, a later file overwrites an
    /// earlier one — caller order is the override order.
    @Test
    func laterSupplementaryFilesOverrideEarlierOnes() async throws {
        let directoryURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let earlierFileURL = try Self.writeAPINotesFile(yaml: """
        Name: EarlierModule
        Tags:
        - Name: TSTStorage
          SwiftName: EarlierSpelling
        """, into: directoryURL, named: "EarlierModule.apinotes")
        let laterFileURL = try Self.writeAPINotesFile(yaml: """
        Name: LaterModule
        Tags:
        - Name: TSTStorage
          SwiftName: LaterSpelling
        """, into: directoryURL, named: "LaterModule.apinotes")

        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(supplementaryAPINotesFiles: [
            try APINotesFile(path: earlierFileURL.path(percentEncoded: false)),
            try APINotesFile(path: laterFileURL.path(percentEncoded: false)),
        ])

        #expect(await typeDatabase.swiftName(forCName: "TSTStorage", category: .valueType) == "LaterSpelling")
    }

    // MARK: - Supplied locations

    /// A location may be a directory (its immediate `.apinotes` entries load
    /// in file-name order) or a single file; unparsable and missing entries
    /// are skipped, never fatal.
    @Test
    func suppliedLocationsExpandDirectoriesAndSkipBrokenEntries() throws {
        let directoryURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        _ = try Self.writeAPINotesFile(yaml: """
        Name: FirstModule
        Typedefs:
        - Name: TSTFirstRef
          SwiftName: First
        """, into: directoryURL, named: "AFirst.apinotes")
        _ = try Self.writeAPINotesFile(yaml: """
        Name: SecondModule
        Typedefs:
        - Name: TSTSecondRef
          SwiftName: Second
        """, into: directoryURL, named: "BSecond.apinotes")
        _ = try Self.writeAPINotesFile(yaml: "{ not apinotes", into: directoryURL, named: "CBroken.apinotes")
        _ = try Self.writeAPINotesFile(yaml: "ignored", into: directoryURL, named: "NotAPINotes.txt")
        let standaloneFileURL = try Self.writeAPINotesFile(yaml: """
        Name: StandaloneModule
        Typedefs:
        - Name: TSTStandaloneRef
          SwiftName: Standalone
        """, into: FileManager.default.temporaryDirectory, named: "SupplementaryAPINotesTests-standalone-\(UUID().uuidString).apinotes")
        defer { try? FileManager.default.removeItem(at: standaloneFileURL) }
        let missingURL = directoryURL.appending(component: "Missing.apinotes")

        let loadedFiles = SupplementaryAPINotesLoader.files(atSupplementaryLocations: [directoryURL, standaloneFileURL, missingURL])
        #expect(loadedFiles.map(\.moduleName) == ["FirstModule", "SecondModule", "StandaloneModule"])
    }
}

#endif
