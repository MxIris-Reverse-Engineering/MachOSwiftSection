import Foundation

/// The family a per-image cache belongs to, for eviction.
///
/// An image's cached state is dropped per family rather than per cache:
/// the declaration indexer claims, when it prepares an image, every family
/// that has no finished entry for that image yet — those are the ones its
/// preparation is about to build — and the image's last live indexer evicts
/// what was claimed (``SharedCacheRegistry``).
///
/// This module declares **no** families. The module that owns a cache
/// declares its family as a static constant in an extension, next to the
/// cache, and names it at the cache's creation:
///
/// ```swift
/// extension SharedCacheEvictionGroup {
///     package static let symbolStore = SharedCacheEvictionGroup("symbolStore")
/// }
///
/// private let cache = SharedCache<Storage>(evictionGroup: .symbolStore)
/// ```
///
/// A cache whose entries point into another family's storage says so with
/// `follows:` — `SharedCache(evictionGroup: .symbolicMangling, follows: [.symbolStore])`
/// — and the registry evicts its family whenever the followed family is
/// claimed and evicted, so an eviction never leaves behind a reference that
/// pins what it just dropped. The relationship is declared by the cache that
/// holds the reference, where the fact is known; this module keeps only the
/// mechanism.
///
/// Two families are the same family when their names are equal; a name is
/// therefore chosen once, by the module that owns it.
@_spi(Internals)
public struct SharedCacheEvictionGroup: Hashable, Sendable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String {
        name
    }
}
