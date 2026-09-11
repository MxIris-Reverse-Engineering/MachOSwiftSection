import Foundation
import MachOKit
import MachOBase

/// A generic struct's or enum's metadata instantiation pattern.
///
/// The field worth having is ``valueWitnessesOffset``: the value witness
/// table the pattern hands every instantiation. For a generic type whose
/// layout does not depend on its arguments that table is the compiler's own
/// answer for size, stride, alignment and extra inhabitants — computed at
/// build time and never recomputed at runtime.
///
/// Mirrors `swift::TargetGenericValueMetadataPattern`
/// (`swift/ABI/Metadata.h`). Reached from a struct or enum descriptor's
/// ``TypeGenericContextDescriptorHeader/defaultInstantiationPatternOffset``;
/// a class descriptor's leads to ``GenericClassMetadataPattern`` instead.
@LocatableLayoutWrapping
public struct GenericValueMetadataPattern: GenericMetadataPatternProtocol {
    public struct Layout: GenericMetadataPatternLayout {
        public let instantiationFunction: RelativeDirectRawPointer
        public let completionFunction: RelativeDirectRawPointer
        public let patternFlags: GenericMetadataPatternFlags
        public let valueWitnesses: RelativeIndirectableRawPointer
    }
}

extension GenericValueMetadataPattern {
    /// A value pattern has at most one trailing partial pattern: the
    /// extra-data one. The immediate-members bit is class-only, and on a
    /// value pattern those bits belong to the metadata kind.
    public var numberOfTrailingPartialPatterns: Int {
        hasExtraDataPattern ? 1 : 0
    }

    /// The metadata kind the instantiation produces, or `nil` when the flags
    /// hold a kind this library does not recognize.
    public var metadataKind: MetadataKind? {
        layout.patternFlags.valueMetadataKind
    }

    /// File offset of the value witness table, or `nil` when the pointer is
    /// null or indirect.
    ///
    /// The pointer is relative-**indirectable**: the compiler may reuse a
    /// table from another library by storing a pointer to a pointer, with the
    /// low bit set to say so. Only the direct case yields an offset within
    /// this image; ``valueWitnessesIsIndirect`` distinguishes them.
    public var valueWitnessesOffset: Int? {
        guard layout.valueWitnesses.isValid, !valueWitnessesIsIndirect else { return nil }
        return layout.valueWitnesses.resolveDirectOffset(from: offset(of: \.valueWitnesses))
    }

    /// Whether the value witness table pointer is indirect — that is, whether
    /// it points at a pointer to the table rather than at the table.
    public var valueWitnessesIsIndirect: Bool {
        layout.valueWitnesses.isIndirect
    }
}
