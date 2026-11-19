import Foundation
import SwiftStdlibToolbox

/// Generic flags build upwards from bit 0; type-specific flags build
/// downwards from bit 15.
///
/// Mirrors `swift::TypeContextDescriptorFlags` (`swift/ABI/MetadataValues.h`).
public struct TypeContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// Whether there is something unusual about how the metadata is
    /// initialized: 0 for nothing, 1 for singleton and 2 for foreign
    /// metadata initialization.
    @BitField(bits: 0..<2)
    private var metadataInitialization: UInt8

    public var noMetadataInitialization: Bool {
        metadataInitialization == 0
    }

    public var hasSingletonMetadataInitialization: Bool {
        metadataInitialization == 1
    }

    public var hasForeignMetadataInitialization: Bool {
        metadataInitialization == 2
    }

    @BitField(bits: 2)
    public var hasImportInfo: Bool

    @BitField(bits: 3)
    public var hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool

    @BitField(bits: 4)
    public var hasLayoutString: Bool

    @BitField(bits: 6)
    public var classHasDefaultOverrideTable: Bool

    @BitField(bits: 7)
    public var classIsActor: Bool

    @BitField(bits: 8)
    public var classIsDefaultActor: Bool

    /// The kind of reference the class makes to its resilient superclass's
    /// descriptor, or `nil` for a kind this reader does not know.
    @BitField(bits: 9..<12)
    public var classResilientSuperclassReferenceKind: TypeReferenceKind?

    @BitField(bits: 12)
    public var classAreImmdiateMembersNegative: Bool

    @BitField(bits: 13)
    public var classHasResilientSuperclass: Bool

    @BitField(bits: 14)
    public var classHasOverrideTable: Bool

    @BitField(bits: 15)
    public var classHasVTable: Bool
}
