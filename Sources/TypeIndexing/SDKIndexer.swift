#if os(macOS)

import APINotes
import Foundation
import FoundationToolbox

/// A Swift module discovered in an SDK: just its name and on-disk location.
/// Discovery is deliberately this cheap — interface generation (the expensive
/// sourcekitd work) happens later, only for the modules a binary's dependency
/// filter selects.
@available(macOS 13.0, *)
package struct SwiftModuleDescriptor: Sendable, Hashable {
    package let moduleName: String
    package let path: String
}

/// A parsed `.apinotes` file: the compiler's authoritative record of how a
/// module's C declarations surface in Swift (renames, availability).
@available(macOS 13.0, *)
package struct APINotesFile: Sendable {
    package let path: String
    package let moduleName: String
    package let apiNotesModule: APINotes.Module

    package init(path: String) throws {
        let apiNotesModule = try APINotes.Module(contentsOf: URL(fileURLWithPath: path))
        self.path = path
        self.moduleName = apiNotesModule.name
        self.apiNotesModule = apiNotesModule
    }
}

extension APINotes.Module: @unchecked @retroactive Sendable {}

/// Everything one SDK scan finds: Swift modules (by name and path only) and
/// parsed APINotes files.
@available(macOS 13.0, *)
package struct SDKDiscovery: Sendable {
    package let modules: [SwiftModuleDescriptor]
    package let apiNotesFiles: [APINotesFile]
}

/// Walks an SDK's module-bearing directories and reports what is there.
///
/// This is pure file-system discovery — it never touches sourcekitd, so a full
/// SDK scan is fast. The historical design generated every discovered module's
/// interface *during* the scan, which made first-time indexing hour-scale and
/// made the caller's module filter pointless (evolution proposal 0008).
@available(macOS 13.0, *)
package struct SDKIndexer {
    package let platform: SDKPlatform

    /// SDK-relative directories scanned for `.swiftmodule` and `.apinotes`
    /// entries, in priority order (an earlier hit wins a module-name tie).
    package let searchPaths: [String]

    package init(
        platform: SDKPlatform,
        searchPaths: [String] = [
            "usr/include",
            "usr/lib/swift",
            "System/Library/Frameworks",
            "System/Library/PrivateFrameworks",
        ]
    ) {
        self.platform = platform
        self.searchPaths = searchPaths
    }

    package func discover(sdkSettings: SDKSettings) -> SDKDiscovery {
        var modulesByName: [String: SwiftModuleDescriptor] = [:]
        var orderedModules: [SwiftModuleDescriptor] = []
        var apiNotesFiles: [APINotesFile] = []
        let fileManager = FileManager.default

        for searchPath in searchPaths {
            let searchURL = URL(fileURLWithPath: sdkSettings.sdkPath).appending(path: searchPath)
            guard fileManager.fileExists(atPath: searchURL.path(percentEncoded: false)) else { continue }
            guard let enumerator = fileManager.enumerator(at: searchURL, includingPropertiesForKeys: nil) else { continue }

            while let entryURL = enumerator.nextObject() as? URL {
                switch entryURL.pathExtension {
                case "swiftmodule":
                    // A `.swiftmodule` is a directory of per-architecture
                    // binaries; nothing inside it is a further module.
                    enumerator.skipDescendants()
                    let moduleName = entryURL.deletingPathExtension().lastPathComponent
                    guard modulesByName[moduleName] == nil else { continue }
                    let descriptor = SwiftModuleDescriptor(moduleName: moduleName, path: entryURL.path(percentEncoded: false))
                    modulesByName[moduleName] = descriptor
                    orderedModules.append(descriptor)
                case "apinotes":
                    do {
                        let apiNotesFile = try APINotesFile(path: entryURL.path(percentEncoded: false))
                        apiNotesFiles.append(apiNotesFile)
                    } catch {
                        #log(.error, "Skipping unparsable APINotes file at \(entryURL.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                default:
                    continue
                }
            }
        }

        #log(.info, "SDK discovery (\(self.platform.rawValue, privacy: .public) \(sdkSettings.cacheDirectoryComponent, privacy: .public)): \(orderedModules.count) Swift modules, \(apiNotesFiles.count) APINotes files")
        return SDKDiscovery(modules: orderedModules, apiNotesFiles: apiNotesFiles)
    }
}

// Protocol-form `@Loggable`: the macro's direct type form expands a static
// stored `logger` carrying its own availability annotation, which an
// `@available(macOS 13.0, *)` type rejects ("cannot be more available than
// enclosing scope"). The un-annotated protocol sidesteps that; the annotated
// extension scopes the conformance.
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.typeindexing", category: "SDKIndexer")
fileprivate protocol SDKIndexerLogging {}

@available(macOS 13.0, *)
extension SDKIndexer: SDKIndexerLogging {}

#endif
