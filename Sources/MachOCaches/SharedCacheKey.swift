import Foundation
import MachOKit
import MachOKitExtensions

/// The key a ``SharedCache`` entry is filed under: a Mach-O reader's
/// identity, hashed on the cheapest part that already tells images apart.
///
/// Every reader's `identifier` is a `MachOTargetIdentifier` today (the two
/// conformers are `MachOFile` and `MachOImage`). Boxing it into an
/// `AnyHashable` on each lookup allocated — the `uuidFile` payload, a path
/// plus a UUID, does not fit an existential's inline buffer — and hashed the
/// whole install path, on lookups that happen once per symbol and once per
/// mangled name. Here the `uuidFile` case hashes only its UUID (unique per
/// link, so it separates images by itself) and the `image` case only its
/// base address; the path takes part in equality, never in the hash. The
/// two cases without a UUID, `file` and `versionedFile`, still hash the
/// path — they only occur for a binary that carries no `LC_UUID`.
///
/// An identifier of any other type is boxed the way it used to be, so a
/// future conformer keeps working, just without the cheaper hash.
@_spi(Internals)
public struct SharedCacheKey: Hashable, CustomStringConvertible, @unchecked Sendable {
    private enum Representation: Hashable {
        case target(MachOTargetIdentifier)
        case opaque(AnyHashable)
    }

    private let representation: Representation

    /// The key of `machO`'s cache entries.
    public init(_ machO: some MachORepresentableWithCache) {
        if let identifier = machO.identifier as? MachOTargetIdentifier {
            self.init(identifier: identifier)
        } else {
            self.init(opaque: machO.identifier)
        }
    }

    /// The key for a reader whose identifier is `identifier`.
    public init(identifier: MachOTargetIdentifier) {
        representation = .target(identifier)
    }

    /// A key for something that is not a Mach-O reader. The cache's own
    /// process-scoped entry and its tests use this; a reader whose
    /// identifier is not a `MachOTargetIdentifier` lands here as well.
    public init(opaque value: some Hashable) {
        representation = .opaque(AnyHashable(value))
    }

    public func hash(into hasher: inout Hasher) {
        switch representation {
        case .target(.uuidFile(_, let uuid)):
            hasher.combine(0 as UInt8)
            hasher.combine(uuid)
        case .target(.image(let baseAddress)):
            hasher.combine(1 as UInt8)
            hasher.combine(baseAddress)
        case .target(let identifier):
            hasher.combine(2 as UInt8)
            hasher.combine(identifier)
        case .opaque(let value):
            hasher.combine(3 as UInt8)
            hasher.combine(value)
        }
    }

    // `==` is the synthesized one over `representation`: the full
    // identifier, path included, decides equality.

    public var description: String {
        switch representation {
        case .target(let identifier):
            return String(describing: identifier)
        case .opaque(let value):
            return String(describing: value.base)
        }
    }
}
