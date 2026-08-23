#if os(macOS)

import Foundation
import Testing
@testable import TypeIndexing

/// The cache-write discipline of `ModuleInterfaceIndexer`, driven through its
/// interface-generator test seam — no sourcekitd.
@Suite
struct ModuleInterfaceIndexerTests {
    private static func makeCache() throws -> ModuleIndexCache {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(component: "ModuleInterfaceIndexerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return ModuleIndexCache(directoryURL: directoryURL)
    }

    private static func makeIndexer(cache: ModuleIndexCache, interfaceGenerator: @escaping ModuleInterfaceIndexer.InterfaceGenerator) -> ModuleInterfaceIndexer {
        ModuleInterfaceIndexer(
            platform: .macOS,
            sdkSettings: SDKSettings(sdkPath: "/nonexistent-sdk", version: "0.0", productBuildVersion: nil),
            cache: cache,
            interfaceGenerator: interfaceGenerator
        )
    }

    private static func interface(moduleName: String, typeNames: [String], importedModuleNames: [String] = []) -> SourceKitManager.GeneratedModuleInterface {
        SourceKitManager.GeneratedModuleInterface(
            moduleName: moduleName,
            sourceText: "",
            declarations: typeNames.map { InterfaceDeclarationNode(kind: .typeDeclaration, name: $0) },
            importedModuleNames: importedModuleNames
        )
    }

    enum StubError: Error {
        case submoduleTimedOut
    }

    /// A submodule whose generation fails degrades the entry for THIS run but
    /// must not be cached: the cache has no completeness marker, so a stored
    /// partial entry would freeze the gap until the SDK or generator version
    /// changes (PR #110 review, finding 4).
    @Test
    func partialEntryIsServedButNeverCached() async throws {
        let cache = try Self.makeCache()
        let indexer = Self.makeIndexer(cache: cache) { moduleName in
            if moduleName == "Foo" {
                return Self.interface(moduleName: "Foo", typeNames: ["FooType"], importedModuleNames: ["Foo.Sub", "Unrelated"])
            }
            throw StubError.submoduleTimedOut
        }

        let entry = await indexer.indexEntry(forModuleNamed: "Foo")
        #expect(entry?.typeNames == ["FooType"])
        #expect(cache.entry(forModuleNamed: "Foo") == nil)
    }

    @Test
    func completeEntryIsCached() async throws {
        let cache = try Self.makeCache()
        let indexer = Self.makeIndexer(cache: cache) { moduleName in
            switch moduleName {
            case "Foo":
                return Self.interface(moduleName: "Foo", typeNames: ["FooType"], importedModuleNames: ["Foo.Sub"])
            case "Foo.Sub":
                return Self.interface(moduleName: "Foo.Sub", typeNames: ["SubType"])
            default:
                throw StubError.submoduleTimedOut
            }
        }

        let entry = await indexer.indexEntry(forModuleNamed: "Foo")
        #expect(entry?.typeNames == ["FooType", "SubType"])
        #expect(cache.entry(forModuleNamed: "Foo")?.typeNames == ["FooType", "SubType"])
    }

    /// The whole module failing still returns `nil` and caches nothing — the
    /// pre-existing contract, pinned alongside the partial-entry rule.
    @Test
    func failedModuleCachesNothing() async throws {
        let cache = try Self.makeCache()
        let indexer = Self.makeIndexer(cache: cache) { _ in
            throw StubError.submoduleTimedOut
        }

        let entry = await indexer.indexEntry(forModuleNamed: "Foo")
        #expect(entry == nil)
        #expect(cache.entry(forModuleNamed: "Foo") == nil)
    }
}

#endif
