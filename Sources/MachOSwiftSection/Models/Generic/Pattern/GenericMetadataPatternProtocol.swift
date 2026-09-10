import Foundation
import MachOKit
import MachOBase

/// The header every generic metadata instantiation pattern starts with.
///
/// Mirrors `swift::TargetGenericMetadataPattern` (`swift/ABI/Metadata.h`),
/// which the value and class patterns extend by C++ inheritance; here they
/// share it by conforming to ``GenericMetadataPatternProtocol``.
public protocol GenericMetadataPatternLayout: LayoutProtocol {
    var instantiationFunction: RelativeDirectRawPointer { get }
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
public protocol GenericMetadataPatternProtocol: ResolvableLocatableLayoutWrapper where Layout: GenericMetadataPatternLayout {
    /// Number of ``GenericMetadataPartialPattern``s trailing the pattern.
    var numberOfTrailingPartialPatterns: Int { get }

    /// File offset of the function that allocates and populates the
    /// metadata, or `nil` for a null pointer.
    ///
    /// A requirement rather than a shared implementation because resolving it
    /// needs the field's offset within the CONCRETE layout, and a key path
    /// formed against the layout protocol addresses a witness rather than a
    /// stored property — `MemoryLayout.offset(of:)` answers nil for it.
    var instantiationFunctionOffset: Int? { get }

    /// File offset of the function that finishes an incomplete
    /// instantiation, or `nil` when there is none — in which case the
    /// instantiation function must always produce complete metadata. A
    /// requirement for the same reason as ``instantiationFunctionOffset``.
    var completionFunctionOffset: Int? { get }
}

extension GenericMetadataPatternProtocol {
    public var patternFlags: GenericMetadataPatternFlags { layout.patternFlags }

    /// Whether a partial pattern for extra data trails this pattern.
    public var hasExtraDataPattern: Bool { patternFlags.hasExtraDataPattern }

    /// Whether instantiated metadata carries a trailing flag word.
    public var hasTrailingFlags: Bool { patternFlags.hasTrailingFlags }

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
