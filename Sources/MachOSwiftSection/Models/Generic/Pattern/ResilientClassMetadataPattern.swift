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
        public let relocationFunction: RelativeDirectRawPointer
        public let destroy: RelativeDirectRawPointer
        public let instanceVariableDestroyer: RelativeDirectRawPointer
        public let classFlags: UInt32
        public let data: RelativeDirectRawPointer
        public let metaclass: RelativeDirectRawPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ResilientClassMetadataPattern {
    /// The raw class flag word (`swift::ClassFlags`). Reported raw because
    /// the word is a bitfield while ``ClassFlags`` enumerates single bits.
    public var classFlags: UInt32 { layout.classFlags }

    /// File offset of the function that allocates the metadata at the right
    /// size, or `nil` when there is none — in which case the runtime calls
    /// `swift_relocateClassMetadata` with this pattern.
    public var relocationFunctionOffset: Int? {
        guard layout.relocationFunction.isValid else { return nil }
        return layout.relocationFunction.resolveDirectOffset(from: offset(of: \.relocationFunction))
    }

    /// File offset of the heap destructor, or `nil` for a null pointer.
    public var destroyOffset: Int? {
        guard layout.destroy.isValid else { return nil }
        return layout.destroy.resolveDirectOffset(from: offset(of: \.destroy))
    }

    /// File offset of the instance-variable destructor (`IVarDestroyer` in
    /// the ABI), or `nil` when the class needs none.
    public var instanceVariableDestroyerOffset: Int? {
        guard layout.instanceVariableDestroyer.isValid else { return nil }
        return layout.instanceVariableDestroyer.resolveDirectOffset(from: offset(of: \.instanceVariableDestroyer))
    }

    /// File offset of the class's `class_ro_t`, or `nil` for a null pointer.
    /// Only present under Objective-C interop.
    public var dataOffset: Int? {
        guard layout.data.isValid else { return nil }
        return layout.data.resolveDirectOffset(from: offset(of: \.data))
    }

    /// File offset of the metaclass object, or `nil` for a null pointer.
    /// Only present under Objective-C interop.
    public var metaclassOffset: Int? {
        guard layout.metaclass.isValid else { return nil }
        return layout.metaclass.resolveDirectOffset(from: offset(of: \.metaclass))
    }
}
