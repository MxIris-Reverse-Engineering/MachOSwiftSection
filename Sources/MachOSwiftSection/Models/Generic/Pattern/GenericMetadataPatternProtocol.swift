import Foundation
import MachOKit
import MachOBase

/// The header every generic metadata instantiation pattern starts with.
///
/// Mirrors `swift::TargetGenericMetadataPattern` (`swift/ABI/Metadata.h`),
/// which the value and class patterns extend by C++ inheritance; here they
/// share it by conforming to ``GenericMetadataPatternProtocol``.
public protocol GenericMetadataPatternLayout: LayoutProtocol {
    /// Allocates and populates the metadata.
    var instantiationFunction: RelativeDirectRawPointer { get }
    /// Finishes an incomplete instantiation. **Null is meaningful**: it says
    /// the instantiation function always produces complete metadata and no
    /// second pass is needed.
    var completionFunction: RelativeDirectRawPointer { get }
    var patternFlags: GenericMetadataPatternFlags { get }
}

/// A generic type's instantiation pattern: the template the runtime copies
/// and completes to produce metadata for one set of generic arguments.
///
/// Reached from a generic type descriptor's
/// ``TypeGenericContextDescriptorHeader/defaultInstantiationPatternOffset``.
/// Which conformer to resolve is decided by the descriptor's kind:
/// ``GenericClassMetadataPattern`` for a class, ``GenericValueMetadataPattern``
/// for a struct or enum.
/// > Note: the two function pointers in the shared header —
/// > `instantiationFunction` and `completionFunction` — are read with
/// > `resolvedDirectOffset(from:)` at the concrete type, never through this
/// > protocol. A key path formed here would address a layout witness rather
/// > than a stored property, and the offset lookup behind that helper
/// > answers nil for it.
public protocol GenericMetadataPatternProtocol: ResolvableLocatableLayoutWrapper where Layout: GenericMetadataPatternLayout {
    /// Number of ``GenericMetadataPartialPattern``s trailing the pattern.
    var numberOfTrailingPartialPatterns: Int { get }
}

extension GenericMetadataPatternProtocol {
    /// Whether a partial pattern for extra data trails this pattern.
    public var hasExtraDataPattern: Bool { layout.patternFlags.hasExtraDataPattern }

    /// Whether instantiated metadata carries a trailing flag word.
    public var hasTrailingFlags: Bool { layout.patternFlags.hasTrailingFlags }

    /// Location of the first trailing ``GenericMetadataPartialPattern``, in
    /// the same coordinate space as ``offset``.
    public var partialPatternsOffset: Int {
        offset + MemoryLayout<Layout>.size
    }

    /// Total length in bytes of the pattern, trailing partial patterns
    /// included.
    public var size: Int {
        MemoryLayout<Layout>.size
            + numberOfTrailingPartialPatterns * MemoryLayout<GenericMetadataPartialPattern.Layout>.size
    }

    public func partialPatterns<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [GenericMetadataPartialPattern] {
        guard numberOfTrailingPartialPatterns > 0 else { return [] }
        return try machO.readWrapperElements(offset: partialPatternsOffset, numberOfElements: numberOfTrailingPartialPatterns)
    }

    public func partialPatterns<Context: ReadingContext>(in context: Context) throws -> [GenericMetadataPartialPattern] {
        guard numberOfTrailingPartialPatterns > 0 else { return [] }
        return try context.readWrapperElements(at: try context.addressFromOffset(partialPatternsOffset), numberOfElements: numberOfTrailingPartialPatterns)
    }

    /// The extra-data partial pattern, or `nil` when the flags say there is
    /// none. Always the first trailing pattern when present.
    public func extraDataPattern<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericMetadataPartialPattern? {
        guard hasExtraDataPattern else { return nil }
        return try partialPatterns(in: machO).first
    }
}
