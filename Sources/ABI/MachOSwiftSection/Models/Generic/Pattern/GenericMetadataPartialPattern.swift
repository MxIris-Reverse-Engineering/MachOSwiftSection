import Foundation
import MachOKit
import MachOBase

/// One block of words to be copied into freshly instantiated metadata.
///
/// A generic metadata pattern is a template: the runtime allocates the
/// metadata, copies these blocks in at the recorded word offsets, then fills
/// the rest from the generic arguments. Both offset and size are counted in
/// **words**, not bytes.
///
/// Mirrors `swift::TargetGenericMetadataPartialPattern`
/// (`swift/ABI/Metadata.h`).
@LocatableLayoutWrapping
public struct GenericMetadataPartialPattern: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        /// The words to copy.
        public let pattern: RelativeDirectRawPointer
        /// Where the block lands in the instantiated metadata, in words. For
        /// value metadata the position is relative to the end of the metadata
        /// header; for class metadata, to the end of the whole class
        /// metadata.
        public let offsetInWords: UInt16
        /// Length of the block, in words.
        public let sizeInWords: UInt16
    }
}
