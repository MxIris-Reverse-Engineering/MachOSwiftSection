import Foundation

public struct TypeContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
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
    
    public var hasSingletonMetadataInitialization: Bool {
        field(firstBit: Bits.metadataInitialization, bitWidth: Bits.metadataInitializationWidth, fieldType: UInt8.self) == 1
    }
    
    public var hasForeignMetadataInitialization: Bool {
        field(firstBit: Bits.metadataInitialization, bitWidth: Bits.metadataInitializationWidth, fieldType: UInt8.self) == 2
    }
    
    public var hasImportInfo: Bool {
        flag(bit: Bits.hasImportInfo)
    }
    
    public var hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool {
        flag(bit: Bits.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer)
    }
    
    public var hasLayoutString: Bool {
        flag(bit: Bits.hasLayoutString)
    }
    
    public var classHasDefaultOverrideTable: Bool {
        flag(bit: Bits.classHasDefaultOverrideTable)
    }
    
    public var classIsActor: Bool {
        flag(bit: Bits.classIsActor)
    }
    
    public var classIsDefaultActor: Bool {
        flag(bit: Bits.classIsDefaultActor)
    }
    
    public var classResilientSuperclassReferenceKind: TypeReferenceKind {
        let rawValue = field(firstBit: Bits.classResilientSuperclassReferenceKind, bitWidth: Bits.classResilientSuperclassReferenceKindWidth, fieldType: UInt8.self)
        return .init(rawValue: rawValue)!
    }
    
    public var classAreImmdiateMembersNegative: Bool {
        flag(bit: Bits.classAreImmdiateMembersNegative)
    }
    
    public var classHasResilientSuperclass: Bool {
        flag(bit: Bits.classHasResilientSuperclass)
    }
    
    public var classHasOverrideTable: Bool {
        flag(bit: Bits.classHasOverrideTable)
    }
    
    public var classHasVTable: Bool {
        flag(bit: Bits.classHasVTable)
    }
}

public enum TypeReferenceKind: UInt8 {
    case directTypeDescriptor
    case indirectTypeDescriptor
    case directObjCClassName
    case indirectObjCClass
}
