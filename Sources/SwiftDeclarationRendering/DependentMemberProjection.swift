import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachODependencies
import SwiftLayout
import SwiftThunkAnalysis
@_spi(Internals) import MachOCaches
import Demangling

/// The image universes the opaque rewriter projects members through
/// (evolution proposal `opaque-reference-spelling-and-member-projection`),
/// one per root image and search-path set, built on first use.
///
/// A projection walks the root's dependency closure for the conformance
/// whose record answers — `IndexingIterator<[Int]>.Element` is answered by
/// libswiftCore — so the universe is `SwiftLayout`'s
/// ``ImageUniverse/dependencyClosure(root:searchPaths:)``, the same index
/// the static layout engine folds in lazily. Building one resolves the whole
/// closure's load commands, which is why it is cached process-wide the way
/// `DependencyImageResolver` is, and keyed by search paths the way that
/// resolver keys its lookups: two tasks may scope different paths for the
/// same file.
///
/// Offline, the search paths are the ones by-name opaque expansion uses —
/// the task-scoped ``DisassemblingAccessorThunkResolver``'s, else the paths
/// inferred from where the file sits — plus the host's shared cache, which
/// is where the standard library's records are and which an explicit path
/// list otherwise leaves out. In-process, the closure is the loaded images.
///
/// `ImageUniverse` memoizes without internal synchronization; every use is
/// serialized through the entry's lock.
package enum DependentMemberProjection {
    /// A universe and the lock its uses go through.
    final class Entry<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
        let universe: ImageUniverse<MachO>
        private let lock = NSLock()

        init(universe: ImageUniverse<MachO>) {
            self.universe = universe
        }

        func withUniverse<Result>(_ body: (ImageUniverse<MachO>) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(universe)
        }
    }

    /// The universes of one file, one per search-path set.
    final class FileRegistry: @unchecked Sendable {
        private let root: MachOFile
        private let lock = NSLock()
        private var entriesBySearchPaths: [[DependencySearchPath]: Entry<MachOFile>?] = [:]

        init(root: MachOFile) {
            self.root = root
        }

        func entry(for searchPaths: [DependencySearchPath]) -> Entry<MachOFile>? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = entriesBySearchPaths[searchPaths] { return cached }
            let entry = (try? ImageUniverse.dependencyClosure(root: root, searchPaths: searchPaths)).map { Entry(universe: $0) }
            entriesBySearchPaths[searchPaths] = entry
            return entry
        }
    }

    private static let fileRegistries = SharedCache<FileRegistry>()
    private static let imageEntries = SharedCache<Entry<MachOImage>>()

    /// The search paths a projection from `machOFile` walks: what by-name
    /// opaque expansion walks, plus the host's shared cache.
    package static func searchPaths(for machOFile: MachOFile) -> [DependencySearchPath] {
        let searchPaths = (AccessorThunkResolution.effectiveResolver as? DisassemblingAccessorThunkResolver)?.searchPaths
            ?? MachOThunkEnvironment.defaultSearchPaths(for: machOFile)
        guard !searchPaths.contains(.systemDyldSharedCache) else { return searchPaths }
        return searchPaths + [.systemDyldSharedCache]
    }

    /// Projects `base.Name` through the conformance records reachable from
    /// `machO`, or answers `nil` when the reader is neither a file nor an
    /// in-process image, the universe cannot be built, or the record is not
    /// there. See ``ImageUniverse/projectedAssociatedTypeWitness(base:associatedTypeReference:)``.
    package static func project<MachO: MachOSwiftSectionRepresentableWithCache>(
        base baseTypeNode: Node,
        associatedTypeReference: Node,
        in machO: MachO
    ) -> ImageUniverse<MachO>.ProjectedAssociatedTypeWitness? {
        if let machOFile = machO as? MachOFile {
            let registry = fileRegistries.storage(in: machOFile) { FileRegistry(root: $0) } ?? FileRegistry(root: machOFile)
            guard let entry = registry.entry(for: searchPaths(for: machOFile)) else { return nil }
            let projection = entry.withUniverse { $0.projectedAssociatedTypeWitness(base: baseTypeNode, associatedTypeReference: associatedTypeReference) }
            return projection.flatMap { Self.cast($0) }
        }
        if let machOImage = machO as? MachOImage {
            guard let entry = imageEntries.storage(in: machOImage, buildUsing: { (try? ImageUniverse.dependencyClosure(root: $0)).map { Entry(universe: $0) } }) else { return nil }
            let projection = entry.withUniverse { $0.projectedAssociatedTypeWitness(base: baseTypeNode, associatedTypeReference: associatedTypeReference) }
            return projection.flatMap { Self.cast($0) }
        }
        return nil
    }

    /// The generic-parameter cast the `as?` dispatch above cannot express
    /// directly: a projection made in a `MachOFile` universe is a projection
    /// for `MachO` exactly when `MachO` is `MachOFile`, which the dispatch
    /// established.
    private static func cast<Source: MachOSwiftSectionRepresentableWithCache, MachO: MachOSwiftSectionRepresentableWithCache>(
        _ projection: ImageUniverse<Source>.ProjectedAssociatedTypeWitness
    ) -> ImageUniverse<MachO>.ProjectedAssociatedTypeWitness? {
        guard let image = projection.image as? MachO else { return nil }
        return ImageUniverse<MachO>.ProjectedAssociatedTypeWitness(
            witnessNode: projection.witnessNode,
            image: image,
            conformingQualifiedName: projection.conformingQualifiedName,
            protocolQualifiedName: projection.protocolQualifiedName
        )
    }
}
