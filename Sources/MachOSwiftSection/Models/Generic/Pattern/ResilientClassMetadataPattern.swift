import Foundation
import MachOKit
import MachOBase

/// The instantiation pattern for a **non-generic** class whose ancestry is
/// resilient — at least one superclass lives in another resilience domain.
///
/// Such a class cannot have its metadata laid out at build time, because the
/// superclass may grow between builds, so the metadata is built once at
/// runtime from this pattern (`swift_relocateClassMetadata`, or the pattern's
/// own relocation function when it has one).
///
/// It is **not** reached through
/// ``TypeGenericContextDescriptorHeader/defaultInstantiationPatternOffset``
/// like the generic patterns are — the class is not generic and has no
/// generic context. It hangs off the class's singleton metadata
/// initialization record instead, in the field that otherwise holds the
/// incomplete metadata; see
/// ``SingletonMetadataInitialization/resilientClassPatternOffset``.
///
/// Mirrors `swift::TargetResilientClassMetadataPattern`
/// (`swift/ABI/Metadata.h`).
public struct ResilientClassMetadataPattern: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        /// Allocates the metadata at the right size. **Null is meaningful**:
        /// it tells the runtime to call `swift_relocateClassMetadata` with
        /// this pattern instead.
        public let relocationFunction: RelativeDirectRawPointer
        /// The heap destructor.
        public let destroy: RelativeDirectRawPointer
        /// `IVarDestroyer` in the ABI. Null when the class needs none.
        public let instanceVariableDestroyer: RelativeDirectRawPointer
        /// The raw class flag word (`swift::ClassFlags`). Raw because the
        /// word is a bitfield while ``ClassFlags`` enumerates single bits.
        public let classFlags: UInt32
        /// The class's `class_ro_t`. Only present under Objective-C interop.
        public let data: RelativeDirectRawPointer
        /// The metaclass object. Only present under Objective-C interop.
        public let metaclass: RelativeDirectRawPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
