import MachOKit
import MachOKitExtensions
import MachOSwiftSection

/// The reader re-typings the per-image indexes' build closures make.
///
/// Every index is queried through `MachORepresentableWithCache` — the
/// protocol each consumer holds its reader as — and its `SharedCache` is
/// keyed the same way. Building an index reads descriptors and ObjC class
/// data, which that protocol does not offer; both of its conformers
/// (`MachOFile`, `MachOImage`) do. So a build closure re-types the reader
/// once, here, instead of every index spelling the `MachOFile` /
/// `MachOImage` split itself. Passing the existential to a `some`-typed
/// build opens it (SE-0352), so the builds stay generic.
///
/// A host's `MachOReaderWrapper` is re-typed as the reader beneath it where
/// it cannot answer itself: `ObjCImplementationClassReading` is this
/// module's own, so no wrapper outside it can conform.
extension MachORepresentableWithCache {
    /// `self` as a Swift-section reader — or the reader beneath its wrappers
    /// when `self` is not one — or `nil` for a reader of another kind.
    var swiftSectionReader: (any MachOSwiftSectionRepresentableWithCache)? {
        (self as? any MachOSwiftSectionRepresentableWithCache) ?? (underlyingReader as? any MachOSwiftSectionRepresentableWithCache)
    }

    /// The reader the ObjC-side indexes build from — `self`, or the reader
    /// beneath its wrappers — or `nil` for a reader of another kind.
    var objcImplementationClassReader: (any ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache)? {
        underlyingReader as? any ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache
    }
}
