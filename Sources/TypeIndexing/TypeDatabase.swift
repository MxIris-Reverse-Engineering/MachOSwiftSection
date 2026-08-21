#if os(macOS)

import Foundation
import FoundationToolbox
import MachOKit
import ObjCIndexing
import ObjCMetadataSource

/// The `__C` module-attribution database: answers "which module declares the
/// type named X" for the ObjC/C-imported types Swift manglings spell as
/// `__C.X` / `__ObjC.X`.
///
/// Attribution merges three sources, queried in priority order:
///
/// 1. **Public API** — type names extracted from SourceKit-generated module
///    interfaces (the Swift view of each module, ObjC-imported declarations
///    included), for the modules the indexed binary depends on.
/// 2. **APINotes** — C names registered to their declaring module, covering
///    renamed types whose C spelling never appears in any Swift interface.
///    Written after the interface names, so the compiler's own record wins a
///    conflict.
/// 3. **ObjC metadata (lazy)** — private classes/protocols and harvested C
///    struct/union names read from the binary's dependency images via
///    `ObjCIndexing`. Consulted only on a miss of the first two, one image at
///    a time, stopping at the first hit — declared-in-public-API attribution
///    always outranks "its metadata lives in this image".
@available(macOS 13.0, *)
package actor TypeDatabase<MachO: ObjCMetadataSource & Sendable> {
    private let platform: SDKPlatform

    private let sourceKitManager = SourceKitManager()

    /// Type name → declaring module, merged from interfaces then APINotes.
    private var moduleNamesByTypeName: [String: String] = [:]

    /// Type name → image-derived module, filled lazily from `ObjCIndexing`.
    private var objcModuleNamesByTypeName: [String: String] = [:]

    private var apiNotesIndex = APINotesIndex(files: [])

    /// Dependency images not yet ObjC-indexed, in dependency order. Popped
    /// one at a time as misses demand; an image whose indexing fails is
    /// dropped (logged), not retried.
    private var unindexedDependencies: [MachO] = []

    package init(platform: SDKPlatform) {
        self.platform = platform
    }

    // MARK: - Indexing

    /// Builds the database: discovers the SDK (cheap), then generates and
    /// extracts interfaces only for modules passing `moduleFilter` (expensive,
    /// cached per module per SDK build), registers APINotes attribution, and
    /// records `dependencies` for lazy ObjC indexing.
    package func index(dependencies: [MachO], moduleFilter: @Sendable (String) -> Bool) async throws {
        let sdkSettings = try platform.sdkSettings()
        let discovery = SDKIndexer(platform: platform).discover(sdkSettings: sdkSettings)

        let filteredModules = discovery.modules.filter { moduleFilter($0.moduleName) }
        let moduleInterfaceIndexer = ModuleInterfaceIndexer(
            platform: platform,
            sdkSettings: sdkSettings,
            cache: ModuleIndexCache(platform: platform, sdkSettings: sdkSettings),
            sourceKitManager: sourceKitManager
        )
        let entries = await withTaskGroup(of: ModuleIndexCacheEntry?.self) { group in
            for moduleDescriptor in filteredModules {
                group.addTask {
                    await moduleInterfaceIndexer.indexEntry(forModuleNamed: moduleDescriptor.moduleName)
                }
            }
            var entries: [ModuleIndexCacheEntry] = []
            for await entry in group {
                if let entry {
                    entries.append(entry)
                }
            }
            return entries
        }

        register(moduleEntries: entries)
        register(apiNotesIndex: APINotesIndex(files: discovery.apiNotesFiles))
        register(dependencies: dependencies)
    }

    /// Registers interface-extracted type names. Exposed as a step so merge
    /// priority is unit-testable without sourcekitd.
    package func register(moduleEntries: [ModuleIndexCacheEntry]) {
        for entry in moduleEntries {
            for typeName in entry.typeNames {
                moduleNamesByTypeName[typeName] = entry.moduleName
            }
        }
    }

    /// Registers APINotes attribution (C name → declaring module), overriding
    /// any interface-derived entry for the same name.
    package func register(apiNotesIndex: APINotesIndex) {
        self.apiNotesIndex = apiNotesIndex
        for (cName, moduleName) in apiNotesIndex.moduleNamesByCName {
            moduleNamesByTypeName[cName] = moduleName
        }
    }

    /// Records the images consulted lazily for private-type attribution.
    package func register(dependencies: [MachO]) {
        unindexedDependencies = dependencies
    }

    // MARK: - Query

    package func moduleName(forTypeName typeName: String) async -> String? {
        if let moduleName = moduleNamesByTypeName[typeName] {
            return moduleName
        }
        if let moduleName = objcModuleNamesByTypeName[typeName] {
            return moduleName
        }
        // Lazy ObjC indexing: fold in one dependency image at a time until
        // the name resolves or the images run out. Misses after exhaustion
        // cost one dictionary probe, since nothing remains unindexed.
        while !unindexedDependencies.isEmpty {
            let machO = unindexedDependencies.removeFirst()
            await indexObjCMetadata(of: machO)
            if let moduleName = objcModuleNamesByTypeName[typeName] {
                return moduleName
            }
        }
        return nil
    }

    package func swiftName(forCName cName: String) -> String? {
        apiNotesIndex.swiftName(forCName: cName)?.name
    }

    // MARK: - Lazy ObjC Indexing

    private func indexObjCMetadata(of machO: MachO) async {
        let imagePath = machO.imagePath
        let moduleName = Self.moduleName(forImagePath: imagePath)
        let objcInterfaceIndexer = ObjCInterfaceIndexer(machO: machO, imagePath: imagePath)
        do {
            try await objcInterfaceIndexer.prepare()
        } catch {
            #log(.error, "Skipping ObjC metadata of \(imagePath, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        let discoveredNames = objcInterfaceIndexer.classNames
            + objcInterfaceIndexer.protocolNames
            + objcInterfaceIndexer.structNames
            + objcInterfaceIndexer.unionNames
        for discoveredName in discoveredNames {
            // Never overwrite: the declaring image is whichever dependency
            // came first in dependency order, and interface/APINotes
            // attribution is consulted before this table anyway.
            if objcModuleNamesByTypeName[discoveredName] == nil {
                objcModuleNamesByTypeName[discoveredName] = moduleName
            }
        }
    }

    /// `…/Foundation.framework/Foundation` → `Foundation`,
    /// `libswiftFoundation.dylib` → `Foundation`, `libobjc.A.dylib` →
    /// `libobjc`: every path extension is stripped, then the `libswift`
    /// overlay prefix is removed.
    package static func moduleName(forImagePath imagePath: String) -> String {
        var name = URL(fileURLWithPath: imagePath).lastPathComponent
        while name.contains(".") {
            name = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        }
        if name.hasPrefix("libswift") {
            name = String(name.dropFirst("libswift".count))
        }
        return name
    }
}

// Protocol-form `@Loggable`, required twice over: the type is generic (the
// direct form's static stored logger is illegal there) and carries an
// `@available(macOS 13.0, *)` scope the macro's own annotations would exceed.
// The protocol itself stays un-annotated for the latter reason.
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.typeindexing", category: "TypeDatabase")
fileprivate protocol TypeDatabaseLogging {}

@available(macOS 13.0, *)
extension TypeDatabase: TypeDatabaseLogging {}

#endif
