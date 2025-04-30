import Foundation

struct SwiftTypeContextDescriptorFlags: FlagSet {
    var rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let metadataInitialization = 0
        static let metadataInitializationWidth = 2
        static let hasImportInfo = 2
        static let hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer = 3
        static let hasLayoutString = 4
        static let classHasDefaultOverrideTable = 6
        static let classIsActor = 7
        static let classIsDefaultActor = 8
        static let classResilientSuperclassReferenceKind = 9
        static let classResilientSuperclassReferenceKindWidth = 3
        static let classAreImmdiateMembersNegative = 12
        static let classHasResilientSuperclass = 13
        static let classHasOverrideTable = 14
        static let classHasVTable = 15
    }
}
