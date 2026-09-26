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
@LocatableLayoutWrapping
public struct SingletonMetadataInitialization: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let initializationCacheOffset: RelativeDirectRawPointer
        /// **Union**: the incomplete metadata to complete in place, or — when
        /// the owning descriptor is a class with a resilient superclass — a
        /// ``ResilientClassMetadataPattern``. See the type's documentation;
        /// only the descriptor's `hasResilientSuperclass` flag says which.
        public let incompleteMetadata: RelativeDirectRawPointer
        /// Completes the metadata. Null when the initialization needs no
        /// second pass.
        public let completionFunction: RelativeDirectRawPointer
    }
}
