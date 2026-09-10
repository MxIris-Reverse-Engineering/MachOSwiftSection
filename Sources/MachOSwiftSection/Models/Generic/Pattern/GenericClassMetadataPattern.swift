import Foundation
import MachOKit
import MachOBase

/// A generic class's metadata instantiation pattern.
///
/// Carries what a class needs beyond the shared header: the two destructors,
/// the class flags, and — under Objective-C interop — where the
/// runtime-built `class_ro_t` and metaclass objects land inside the extra
/// data block.
///
/// Mirrors `swift::TargetGenericClassMetadataPattern`
/// (`swift/ABI/Metadata.h`). Note this is the pattern for a **generic**
/// class; a non-generic class with a resilient superclass gets a
/// ``ResilientClassMetadataPattern`` instead, reached through its singleton
/// metadata initialization record.
public struct GenericClassMetadataPattern: GenericMetadataPatternProtocol {
    public struct Layout: GenericMetadataPatternLayout {
        public let instantiationFunction: RelativeDirectRawPointer
        public let completionFunction: RelativeDirectRawPointer
        public let patternFlags: GenericMetadataPatternFlags
        public let destroy: RelativeDirectRawPointer
        public let instanceVariableDestroyer: RelativeDirectRawPointer
        public let classFlags: UInt32
        public let classReadOnlyDataOffsetInWords: UInt16
        public let metaclassObjectOffsetInWords: UInt16
        public let metaclassReadOnlyDataOffsetInWords: UInt16
        public let reserved: UInt16
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericClassMetadataPattern {
    /// See ``GenericMetadataPatternProtocol/instantiationFunctionOffset``.
    public var instantiationFunctionOffset: Int? {
        guard layout.instantiationFunction.isValid else { return nil }
        return layout.instantiationFunction.resolveDirectOffset(from: offset(of: \.instantiationFunction))
    }

    /// See ``GenericMetadataPatternProtocol/completionFunctionOffset``.
    public var completionFunctionOffset: Int? {
        guard layout.completionFunction.isValid else { return nil }
        return layout.completionFunction.resolveDirectOffset(from: offset(of: \.completionFunction))
    }

    /// Whether a second trailing partial pattern describes the class's
    /// immediate members.
    public var hasImmediateMembersPattern: Bool {
        patternFlags.classHasImmediateMembersPattern
    }

    /// A class pattern may trail both an extra-data pattern and an
    /// immediate-members pattern, in that order.
    public var numberOfTrailingPartialPatterns: Int {
        (hasExtraDataPattern ? 1 : 0) + (hasImmediateMembersPattern ? 1 : 0)
    }

    /// The raw class flag word (`swift::ClassFlags`) stamped into every
    /// instantiation. Reported raw because the word is a bitfield while
    /// ``ClassFlags`` enumerates single bits.
    public var classFlags: UInt32 { layout.classFlags }

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

    /// Where the class's `class_ro_t` lands inside the extra data block, in
    /// words. Only meaningful under Objective-C interop.
    public var classReadOnlyDataOffsetInWords: Int { Int(layout.classReadOnlyDataOffsetInWords) }

    /// Where the metaclass object lands inside the extra data block, in
    /// words. Only meaningful under Objective-C interop.
    public var metaclassObjectOffsetInWords: Int { Int(layout.metaclassObjectOffsetInWords) }

    /// Where the metaclass's `class_ro_t` lands inside the extra data block,
    /// in words. Only meaningful under Objective-C interop.
    public var metaclassReadOnlyDataOffsetInWords: Int { Int(layout.metaclassReadOnlyDataOffsetInWords) }

    /// The immediate-members partial pattern, or `nil` when the flags say
    /// there is none. It follows the extra-data pattern when both are
    /// present.
    public func immediateMembersPattern<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericMetadataPartialPattern? {
        guard hasImmediateMembersPattern else { return nil }
        return try partialPatterns(in: machO).last
    }
}
