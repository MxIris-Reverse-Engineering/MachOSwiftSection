import Foundation
import MachOKit
import MachOFoundation
@_spi(Internals) import MachOCaches

/// Finds, among the images a standalone root binary links, the one that
/// exports a given symbol name — the offline stand-in for what dyld does
/// with a GOT bind.
///
/// Inside a shared cache every cross-image call is a rebase to a concrete
/// address and ``CacheImageResolver`` finds the image by address. A file
/// that is not in a cache — a third-party app, an older simulator runtime's
/// framework, a build product — calls into other images through binds, and
/// a bind is a *name* plus the load command it came from. The images are
/// located through `MachODependencies` (the root's direct dependencies, each
/// looked up across the caller's search paths) and the name is searched in
/// their export tries. A specialized accessor is never exported, so a hit
/// is always a descriptor's own accessor, which that image's
/// ``MetadataAccessorIndex`` maps back to the descriptor.
///
/// One resolver per root image, shared process-wide through the same cache
/// ``MetadataAccessorIndex`` uses: ``MachOThunkEnvironment`` is built per
/// thunk, and opening a dependency's file per thunk would open SwiftUICore
/// twenty times for one dump. Search paths key every lookup, since two
/// callers may name different ones for the same root.
package final class DependencyImageResolver: @unchecked Sendable {
    /// Where an exported symbol was found: the image, and the symbol's
    /// `ExportedSymbol.offset` in it — an offset from the mach header, which
    /// ``ThunkAddressSpace/address(forExportedSymbolOffset:)`` turns into an
    /// address.
    package struct Location {
        package let image: MachOFile
        package let exportedSymbolOffset: Int
    }

    private struct LookupKey: Hashable {
        let searchPaths: [DependencySearchPath]
        let name: String
    }

    private let root: MachOFile
    private let lock = NSLock()
    private var imagesBySearchPaths: [[DependencySearchPath]: [MachOFile]] = [:]
    private var locationsByKey: [LookupKey: Location?] = [:]

    private init(root: MachOFile) {
        self.root = root
    }

    package static func resolver(for root: MachOFile) -> DependencyImageResolver {
        cache.storage(in: root) { DependencyImageResolver(root: $0) } ?? DependencyImageResolver(root: root)
    }

    private static let cache = SharedCache<DependencyImageResolver>()

    /// The image among the root's direct dependencies — located through
    /// `searchPaths` — that exports `name`, and where. A bind may spell the
    /// name with or without the leading underscore an export trie carries,
    /// so both are tried. `nil` when no located image exports it, which is
    /// also what an unlocatable dependency looks like.
    package func location(ofExportedSymbol name: String, searchPaths: [DependencySearchPath]) -> Location? {
        let key = LookupKey(searchPaths: searchPaths, name: name)
        lock.lock()
        defer { lock.unlock() }
        if let cached = locationsByKey[key] { return cached }
        var located: Location?
        for image in images(for: searchPaths) {
            for spelling in [name, "_" + name] {
                guard let exported = image.exportTrie?.search(by: spelling), let exportedSymbolOffset = exported.offset else { continue }
                located = Location(image: image, exportedSymbolOffset: exportedSymbolOffset)
                break
            }
            if located != nil { break }
        }
        locationsByKey[key] = located
        return located
    }

    /// The root's direct dependencies as `searchPaths` locate them. Direct,
    /// not transitive: a bind names a library the root itself links (its
    /// ordinal indexes the root's own load commands), so a deeper walk could
    /// only add images the bind cannot refer to. Caller holds `lock`.
    private func images(for searchPaths: [DependencySearchPath]) -> [MachOFile] {
        if let cached = imagesBySearchPaths[searchPaths] { return cached }
        let closure = DependencyClosure(root: root, searchPaths: searchPaths, traversal: .direct)
        imagesBySearchPaths[searchPaths] = closure.images
        return closure.images
    }
}
