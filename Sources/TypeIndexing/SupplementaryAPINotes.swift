#if os(macOS)

import Foundation
import FoundationToolbox

/// Loads supplementary `.apinotes` bundles: community-maintained type
/// mappings for frameworks the SDK carries no module for (evolution proposal
/// 0009). AttributeGraph is the canonical case — its `AG_SWIFT_NAME` renames
/// live only in headers the SDK never ships, so `AttributeGraph.Graph` is
/// unrecoverable from any binary and must come from external knowledge.
///
/// Two sources, loaded in overwrite order (later wins inside
/// `APINotesIndex.register(files:)`):
///
/// 1. **Built-in bundles** shipped as library resources
///    (`Resources/SupplementaryAPINotes/*.apinotes`), contributed through
///    pull-request review.
/// 2. **Host-supplied paths** — files or directories a host application or
///    the CLI (`--supplementary-apinotes`) appends.
///
/// A file that fails to parse is skipped and logged, never fatal — the same
/// contract SDK APINotes discovery follows.
@available(macOS 13.0, *)
package enum SupplementaryAPINotesLoader {
    /// The `.apinotes` bundles shipped inside the library's resource bundle,
    /// sorted by file name so load (and therefore overwrite) order is stable.
    package static func builtinFiles() -> [APINotesFile] {
        guard let resourceURLs = Bundle.module.urls(forResourcesWithExtension: "apinotes", subdirectory: "SupplementaryAPINotes") else {
            #log(.error, "Built-in supplementary APINotes resources are missing from the library bundle")
            return []
        }
        return parseFiles(at: resourceURLs.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    /// The `.apinotes` files at host-supplied locations. Each URL may be a
    /// single file or a directory, whose immediate `.apinotes` entries are
    /// loaded in file-name order; the URLs themselves keep caller order, so a
    /// later path overwrites an earlier one.
    package static func files(atSupplementaryLocations locationURLs: [URL]) -> [APINotesFile] {
        var fileURLs: [URL] = []
        for locationURL in locationURLs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: locationURL.path(percentEncoded: false), isDirectory: &isDirectory) else {
                #log(.error, "Skipping missing supplementary APINotes location \(locationURL.path(percentEncoded: false), privacy: .public)")
                continue
            }
            if isDirectory.boolValue {
                let entryURLs = (try? FileManager.default.contentsOfDirectory(at: locationURL, includingPropertiesForKeys: nil)) ?? []
                fileURLs.append(contentsOf: entryURLs
                    .filter { $0.pathExtension == "apinotes" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else {
                fileURLs.append(locationURL)
            }
        }
        return parseFiles(at: fileURLs)
    }

    private static func parseFiles(at fileURLs: [URL]) -> [APINotesFile] {
        var parsedFiles: [APINotesFile] = []
        for fileURL in fileURLs {
            do {
                parsedFiles.append(try APINotesFile(path: fileURL.path(percentEncoded: false)))
            } catch {
                #log(.error, "Skipping unparsable supplementary APINotes file at \(fileURL.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        return parsedFiles
    }
}

// Protocol-form `@Loggable`: the direct type form's generated static stored
// logger is rejected inside `@available(macOS 13.0, *)` types at
// emit-module time ("cannot be more available than enclosing scope").
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.typeindexing", category: "SupplementaryAPINotes")
fileprivate protocol SupplementaryAPINotesLogging {}

@available(macOS 13.0, *)
extension SupplementaryAPINotesLoader: SupplementaryAPINotesLogging {}

#endif
