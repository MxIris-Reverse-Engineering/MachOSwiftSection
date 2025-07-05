import Foundation
import MachOKit
import MachOMacro
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

public struct Enum: TopLevelType {
    public let descriptor: EnumDescriptor
    public let genericContext: TypeGenericContext?
    public let foreignMetadataInitialization: ForeignMetadataInitialization?
    public let singletonMetadataInitialization: SingletonMetadataInitialization?
    public let canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry]
    public let canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public let canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public let invertibleProtocolSet: InvertibleProtocolSet?
    public let singletonMetadataPointer: SingletonMetadataPointer?

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: EnumDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.typeGenericContext(in: machO)

        if let genericContext {
            currentOffset += genericContext.size
        }

        self.genericContext = genericContext

        let typeFlags = try required(descriptor.flags.kindSpecificFlags?.typeFlags)

        if typeFlags.hasForeignMetadataInitialization {
            self.foreignMetadataInitialization = try machO.readWrapperElement(offset: currentOffset) as ForeignMetadataInitialization
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            self.foreignMetadataInitialization = nil
        }

        if typeFlags.hasSingletonMetadataInitialization {
            self.singletonMetadataInitialization = try machO.readWrapperElement(offset: currentOffset) as SingletonMetadataInitialization
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            self.singletonMetadataInitialization = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalMetadataPrespecializations: [CanonicalSpecializedMetadatasListEntry] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            self.canonicalSpecializedMetadatas = canonicalMetadataPrespecializations
            self.canonicalSpecializedMetadatasListCount = count
            self.canonicalSpecializedMetadatasCachingOnceToken = try machO.readWrapperElement(offset: currentOffset) as CanonicalSpecializedMetadatasCachingOnceToken
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            self.canonicalSpecializedMetadatas = []
            self.canonicalSpecializedMetadatasListCount = nil
            self.canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.hasInvertibleProtocols {
            self.invertibleProtocolSet = try machO.readElement(offset: currentOffset) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            self.singletonMetadataPointer = try machO.readWrapperElement(offset: currentOffset) as SingletonMetadataPointer
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            self.singletonMetadataPointer = nil
        }
    }
}


