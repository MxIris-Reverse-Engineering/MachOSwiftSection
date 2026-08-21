#if os(macOS)

import Foundation
import FoundationToolbox

/// One module's cached extraction: what the indexer needs at query time,
/// without the interface text it was extracted from.
@available(macOS 13.0, *)
package struct ModuleIndexCacheEntry: Codable, Sendable {
    package let moduleName: String

    /// Fully-qualified type names the module (and its indexed submodules)
    /// declares, as extracted from the generated interface's substructure.
    package let typeNames: [String]

    package let subModuleNames: [String]

    /// Bumped when extraction behavior changes; a mismatching entry is
    /// ignored so stale semantics never survive a library update.
    package let generatorVersion: Int

    package static let currentGeneratorVersion = 1

    package init(moduleName: String, typeNames: [String], subModuleNames: [String], generatorVersion: Int = Self.currentGeneratorVersion) {
        self.moduleName = moduleName
        self.typeNames = typeNames
        self.subModuleNames = subModuleNames
        self.generatorVersion = generatorVersion
    }
}

/// Per-module JSON cache of extraction results, segmented per platform and
/// per exact SDK build so an Xcode update can never serve stale entries:
///
/// ```
/// Application Support/MachOSwiftSection/SDKIndexer/<platform>/<version>-<build>/<module>.json
/// ```
///
/// Every entry stands alone — there is no whole-SDK completion marker, so a
/// partially-warmed cache serves what it has and misses the rest. All cache
/// I/O is best-effort: a failure degrades to regeneration, never to an error.
@available(macOS 13.0, *)
package struct ModuleIndexCache: Sendable {
    package let directoryURL: URL

    package init(platform: SDKPlatform, sdkSettings: SDKSettings) {
        self.init(
            directoryURL: URL.applicationSupportDirectory
                .appending(component: "MachOSwiftSection")
                .appending(component: "SDKIndexer")
                .appending(component: platform.rawValue)
                .appending(component: sdkSettings.cacheDirectoryComponent)
        )
    }

    /// Direct-directory form, the seam tests use to keep cache I/O out of the
    /// real Application Support tree.
    package init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    private func entryURL(forModuleNamed moduleName: String) -> URL {
        directoryURL.appending(component: "\(moduleName).json")
    }

    package func entry(forModuleNamed moduleName: String) -> ModuleIndexCacheEntry? {
        let entryURL = entryURL(forModuleNamed: moduleName)
        guard let entryData = try? Data(contentsOf: entryURL) else { return nil }
        do {
            let entry = try JSONDecoder().decode(ModuleIndexCacheEntry.self, from: entryData)
            guard entry.generatorVersion == ModuleIndexCacheEntry.currentGeneratorVersion else { return nil }
            return entry
        } catch {
            #log(.error, "Discarding undecodable cache entry at \(entryURL.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    package func store(_ entry: ModuleIndexCacheEntry) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let entryData = try JSONEncoder().encode(entry)
            try entryData.write(to: entryURL(forModuleNamed: entry.moduleName), options: .atomic)
        } catch {
            #log(.error, "Failed to store cache entry for module \(entry.moduleName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

// Protocol-form `@Loggable` — see the note in SDKIndexer.swift: the direct
// type form clashes with the `@available(macOS 13.0, *)` scope.
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.typeindexing", category: "ModuleIndexCache")
fileprivate protocol ModuleIndexCacheLogging {}

@available(macOS 13.0, *)
extension ModuleIndexCache: ModuleIndexCacheLogging {}

#endif
