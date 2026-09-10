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
public struct GenericMetadataPartialPattern: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let pattern: RelativeDirectRawPointer
        public let offsetInWords: UInt16
        public let sizeInWords: UInt16
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericMetadataPartialPattern {
    /// File offset of the words to copy, or `nil` for a null pointer.
    public var patternOffset: Int? {
        guard layout.pattern.isValid else { return nil }
        return layout.pattern.resolveDirectOffset(from: offset(of: \.pattern))
    }

    /// Where the block lands in the instantiated metadata, in words.
    ///
    /// For value metadata the position is relative to the end of the metadata
    /// header; for class metadata it is relative to the end of the whole
    /// class metadata.
    public var offsetInWords: Int { Int(layout.offsetInWords) }

    /// Length of the block, in words.
    public var sizeInWords: Int { Int(layout.sizeInWords) }
}
