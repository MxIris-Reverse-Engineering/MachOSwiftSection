import MachOKit
import MachOSwiftSection
@_spi(Internals) import MachOCodeReferences

extension CodeImage {
    /// The image's reader as MachOSwiftSection reads it: both kinds of
    /// reader an analyzer makes images of are one. Opened into a `some`
    /// parameter (SE-0352), the reads that need it stay generic.
    var swiftSectionReader: (any MachOSwiftSectionRepresentableWithCache)? {
        reader as? any MachOSwiftSectionRepresentableWithCache
    }
}
