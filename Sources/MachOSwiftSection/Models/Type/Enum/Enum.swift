import Foundation
import MachOKit
import MachOFoundation

// template <typename Runtime>
// class swift_ptrauth_struct_context_descriptor(EnumDescriptor)
//    TargetEnumDescriptor final
//    : public TargetValueTypeDescriptor<Runtime>,
//      public TrailingGenericContextObjects<TargetEnumDescriptor<Runtime>,
//                            TargetTypeGenericContextDescriptorHeader,
//                            additional trailing objects
//                            TargetForeignMetadataInitialization<Runtime>,
//                            TargetSingletonMetadataInitialization<Runtime>,
//                            TargetCanonicalSpecializedMetadatasListCount<Runtime>,
//                            TargetCanonicalSpecializedMetadatasListEntry<Runtime>,
//                            TargetCanonicalSpecializedMetadatasCachingOnceToken<Runtime>,
//                            InvertibleProtocolSet,
//                            TargetSingletonMetadataPointer<Runtime>>

public struct Enum: TopLevelType, ContextProtocol {
    public let descriptor: EnumDescriptor
    public private(set) var genericContext: TypeGenericContext?
    public private(set) var foreignMetadataInitialization: ForeignMetadataInitialization?
    public private(set) var singletonMetadataInitialization: SingletonMetadataInitialization?
    public private(set) var canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry] = []
    public private(set) var canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public private(set) var canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public private(set) var invertibleProtocolSet: InvertibleProtocolSet?
    public private(set) var singletonMetadataPointer: SingletonMetadataPointer?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: EnumDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize
        let genericContext = try descriptor.typeGenericContext(in: machO)
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: machO)
    }
    
    public init(descriptor: EnumDescriptor) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.layoutSize
        let genericContext = try descriptor.typeGenericContext()
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: descriptor.asPointer)
    }
    
    private mutating func initialize<Reader: Readable>(descriptor: EnumDescriptor, currentOffset: inout Int, in reader: Reader) throws {
        
        let typeFlags = try required(descriptor.flags.kindSpecificFlags?.typeFlags)

        if typeFlags.hasForeignMetadataInitialization {
            self.foreignMetadataInitialization = try reader.readWrapperElement(offset: currentOffset) as ForeignMetadataInitialization
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            self.foreignMetadataInitialization = nil
        }

        if typeFlags.hasSingletonMetadataInitialization {
            self.singletonMetadataInitialization = try reader.readWrapperElement(offset: currentOffset) as SingletonMetadataInitialization
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            self.singletonMetadataInitialization = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try reader.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalMetadataPrespecializations: [CanonicalSpecializedMetadatasListEntry] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            self.canonicalSpecializedMetadatas = canonicalMetadataPrespecializations
            self.canonicalSpecializedMetadatasListCount = count
            self.canonicalSpecializedMetadatasCachingOnceToken = try reader.readWrapperElement(offset: currentOffset) as CanonicalSpecializedMetadatasCachingOnceToken
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            self.canonicalSpecializedMetadatas = []
            self.canonicalSpecializedMetadatasListCount = nil
            self.canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.hasInvertibleProtocols {
            self.invertibleProtocolSet = try reader.readElement(offset: currentOffset) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            self.singletonMetadataPointer = try reader.readWrapperElement(offset: currentOffset) as SingletonMetadataPointer
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            self.singletonMetadataPointer = nil
        }
    }
}
