import Foundation
import MachOKit

import MachOFoundation

public struct ClassDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: ClassDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeDirectPointer<MetadataAccessor>
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let superclassType: RelativeDirectPointer<MangledName?>
        public let metadataNegativeSizeInWordsOrResilientMetadataBounds: UInt32
        public let metadataPositiveSizeInWordsOrExtraClassFlags: UInt32
        public let numImmediateMembers: UInt32
        public let numFields: UInt32
        public let fieldOffsetVectorOffset: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ClassDescriptor {
    public var resilientSuperclassReferenceKind: TypeReferenceKind? {
        guard let resilientSuperclassReferenceKind = layout.flags.kindSpecificFlags?.typeFlags?.classResilientSuperclassReferenceKind else {
            return nil
        }
        return resilientSuperclassReferenceKind
    }
    
    public var hasFieldOffsetVector: Bool {
        return layout.fieldOffsetVectorOffset != 0
    }
    
    public var hasDefaultOverrideTable: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classHasDefaultOverrideTable ?? false
    }
    
    public var isActor: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classIsActor ?? false
    }
    
    public var isDefaultActor: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classIsDefaultActor ?? false
    }
    
    public var hasVTable: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classHasVTable ?? false
    }
    
    public var hasOverrideTable: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classHasOverrideTable ?? false
    }
    
    public var hasResilientSuperclass: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classHasResilientSuperclass ?? false
    }
    
    public var areImmediateMembersNegative: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.classAreImmdiateMembersNegative ?? false
    }
    
    public var immediateMemberSize: StoredSize {
        return StoredSize(layout.numImmediateMembers) * MemoryLayout<StoredPointer>.size.cast()
    }
    
    public var nonResilientImmediateMembersOffset: Int32 {
        areImmediateMembersNegative ? -Int32(layout.metadataNegativeSizeInWordsOrResilientMetadataBounds) : Int32(layout.metadataPositiveSizeInWordsOrExtraClassFlags) - Int32(layout.numImmediateMembers)
    }
    
    public var hasObjCResilientClassStub: Bool {
        guard hasResilientSuperclass else { return false }
        return ExtraClassDescriptorFlags(rawValue: layout.metadataPositiveSizeInWordsOrExtraClassFlags).hasObjCResilientClassStub
    }
    
    public func superclassTypeMangledName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName? {
        try layout.superclassType.resolve(from: offset(of: \.superclassType), in: machO)
    }
}
