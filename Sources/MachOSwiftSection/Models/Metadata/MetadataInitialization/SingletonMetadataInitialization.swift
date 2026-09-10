import Foundation
import MachOBase

/// The control structure for a type whose metadata cannot be laid out at
/// build time but is still a singleton — one non-generic type, one metadata
/// record, built once on first use.
///
/// The middle field is a **union** in the ABI. For most types it points at
/// the incomplete metadata to be completed in place; for a class with a
/// resilient superclass it points at a ``ResilientClassMetadataPattern``
/// instead, because the metadata's very size depends on an ancestor that may
/// have changed since this binary was built. The class descriptor's
/// `hasResilientSuperclass` flag is the discriminator, which is why this type
/// exposes both readings and neither can decide on its own which is right.
public struct SingletonMetadataInitialization: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let initializationCacheOffset: RelativeOffset
        /// Union: incomplete metadata, or a resilient class pattern. See the
        /// type's documentation.
        public let incompleteMetadata: RelativeOffset
        public let completionFunction: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension SingletonMetadataInitialization {
    /// File offset of the incomplete metadata, or `nil` for a null pointer.
    ///
    /// Valid only when the owning descriptor is NOT a class with a resilient
    /// superclass; in that case the same field holds a pattern instead, and
    /// ``resilientClassPatternOffset`` is the right reading.
    public var incompleteMetadataOffset: Int? {
        guard layout.incompleteMetadata != 0 else { return nil }
        return offset(of: \.incompleteMetadata) + Int(layout.incompleteMetadata)
    }

    /// File offset of the ``ResilientClassMetadataPattern``, or `nil` for a
    /// null pointer.
    ///
    /// Valid only when the owning descriptor IS a class with a resilient
    /// superclass; otherwise the same field holds the incomplete metadata and
    /// ``incompleteMetadataOffset`` is the right reading. The two accessors
    /// read the same word on purpose — the ABI overlays them and the
    /// descriptor's flag is the discriminator.
    public var resilientClassPatternOffset: Int? {
        incompleteMetadataOffset
    }

    /// File offset of the function that completes the metadata, or `nil`
    /// when the initialization needs none.
    public var completionFunctionOffset: Int? {
        guard layout.completionFunction != 0 else { return nil }
        return offset(of: \.completionFunction) + Int(layout.completionFunction)
    }
}
