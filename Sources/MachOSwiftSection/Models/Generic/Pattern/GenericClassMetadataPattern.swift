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
@LocatableLayoutWrapping
public struct GenericClassMetadataPattern: GenericMetadataPatternProtocol {
    public struct Layout: GenericMetadataPatternLayout {
        public let instantiationFunction: RelativeDirectRawPointer
        public let completionFunction: RelativeDirectRawPointer
        public let patternFlags: GenericMetadataPatternFlags
        /// The heap destructor.
        public let destroy: RelativeDirectRawPointer
        /// `IVarDestroyer` in the ABI. Null when the class needs none.
        public let instanceVariableDestroyer: RelativeDirectRawPointer
        /// The raw class flag word (`swift::ClassFlags`) stamped into every
        /// instantiation. Raw because the word is a bitfield while
        /// ``ClassFlags`` enumerates single bits.
        public let classFlags: UInt32
        /// Where the class's `class_ro_t` lands inside the extra data block,
        /// in words. Only meaningful under Objective-C interop, as are the
        /// two below.
        public let classReadOnlyDataOffsetInWords: UInt16
        /// Where the metaclass object lands inside the extra data block.
        public let metaclassObjectOffsetInWords: UInt16
        /// Where the metaclass's `class_ro_t` lands inside the extra data
        /// block.
        public let metaclassReadOnlyDataOffsetInWords: UInt16
        public let reserved: UInt16
    }
}

extension GenericClassMetadataPattern {
    /// Whether a second trailing partial pattern describes the class's
    /// immediate members.
    public var hasImmediateMembersPattern: Bool {
        layout.patternFlags.classHasImmediateMembersPattern
    }

    /// A class pattern may trail both an extra-data pattern and an
    /// immediate-members pattern, in that order.
    public var numberOfTrailingPartialPatterns: Int {
        (hasExtraDataPattern ? 1 : 0) + (hasImmediateMembersPattern ? 1 : 0)
    }

    /// The immediate-members partial pattern, or `nil` when the flags say
    /// there is none. It follows the extra-data pattern when both are
    /// present.
    public func immediateMembersPattern<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericMetadataPartialPattern? {
        guard hasImmediateMembersPattern else { return nil }
        return try partialPatterns(in: machO).last
    }
}
