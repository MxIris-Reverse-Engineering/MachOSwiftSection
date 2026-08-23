#if os(macOS)

import Foundation
import Testing
@testable import TypeIndexing

@Suite
struct ModuleIndexCacheTests {
    private static func makeTemporaryCache() -> ModuleIndexCache {
        ModuleIndexCache(
            directoryURL: FileManager.default.temporaryDirectory
                .appending(component: "ModuleIndexCacheTests-\(UUID().uuidString)")
        )
    }

    @Test
    func storedEntriesRoundTrip() {
        let cache = Self.makeTemporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directoryURL) }
        let entry = ModuleIndexCacheEntry(
            moduleName: "Foundation",
            typeNames: ["NSString", "NSURLSession.Configuration"],
            subModuleNames: ["Foundation.NSObject"]
        )
        cache.store(entry)
        let loadedEntry = cache.entry(forModuleNamed: "Foundation")
        #expect(loadedEntry?.moduleName == "Foundation")
        #expect(loadedEntry?.typeNames == ["NSString", "NSURLSession.Configuration"])
        #expect(loadedEntry?.subModuleNames == ["Foundation.NSObject"])
    }

    @Test
    func missingEntriesReadAsNil() {
        let cache = Self.makeTemporaryCache()
        #expect(cache.entry(forModuleNamed: "NeverStored") == nil)
    }

    /// An entry written by an older extractor must not survive a generator
    /// bump — stale extraction semantics regenerate instead of being served.
    @Test
    func mismatchedGeneratorVersionInvalidatesTheEntry() {
        let cache = Self.makeTemporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.directoryURL) }
        let outdatedEntry = ModuleIndexCacheEntry(
            moduleName: "Foundation",
            typeNames: ["NSString"],
            subModuleNames: [],
            generatorVersion: ModuleIndexCacheEntry.currentGeneratorVersion - 1
        )
        cache.store(outdatedEntry)
        #expect(cache.entry(forModuleNamed: "Foundation") == nil)
    }
}

#endif
