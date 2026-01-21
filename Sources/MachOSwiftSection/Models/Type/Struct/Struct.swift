import Foundation
import MachOKit
import MachOFoundation

public struct Struct: TopLevelType, ContextProtocol {
    public let descriptor: StructDescriptor
    public private(set) var genericContext: TypeGenericContext?
    public private(set) var foreignMetadataInitialization: ForeignMetadataInitialization?
    public private(set) var singletonMetadataInitialization: SingletonMetadataInitialization?
    public private(set) var canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry] = []
    public private(set) var canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public private(set) var canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public private(set) var invertibleProtocolSet: InvertibleProtocolSet?
    public private(set) var singletonMetadataPointer: SingletonMetadataPointer?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: StructDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.typeGenericContext(in: machO)

        if let genericContext {
            currentOffset += genericContext.size
        }

        self.genericContext = genericContext

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: machO)
    }

    public init(descriptor: StructDescriptor) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.layoutSize

        let genericContext = try descriptor.typeGenericContext()

        if let genericContext {
            currentOffset += genericContext.size
        }

        self.genericContext = genericContext

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: descriptor.asPointer)
    }

    private mutating func initialize<Reader: Readable>(descriptor: StructDescriptor, currentOffset: inout Int, in machO: Reader) throws {
        let typeFlags = try required(descriptor.flags.kindSpecificFlags?.typeFlags)

        if typeFlags.hasForeignMetadataInitialization {
            foreignMetadataInitialization = try machO.readWrapperElement(offset: currentOffset) as ForeignMetadataInitialization
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            foreignMetadataInitialization = nil
        }

        if typeFlags.hasSingletonMetadataInitialization {
            singletonMetadataInitialization = try machO.readWrapperElement(offset: currentOffset) as SingletonMetadataInitialization
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            singletonMetadataInitialization = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalMetadataPrespecializations: [CanonicalSpecializedMetadatasListEntry] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            canonicalSpecializedMetadatas = canonicalMetadataPrespecializations
            canonicalSpecializedMetadatasListCount = count
            canonicalSpecializedMetadatasCachingOnceToken = try machO.readWrapperElement(offset: currentOffset) as CanonicalSpecializedMetadatasCachingOnceToken
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            canonicalSpecializedMetadatas = []
            canonicalSpecializedMetadatasListCount = nil
            canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.hasInvertibleProtocols {
            invertibleProtocolSet = try machO.readElement(offset: currentOffset) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            singletonMetadataPointer = try machO.readWrapperElement(offset: currentOffset) as SingletonMetadataPointer
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            singletonMetadataPointer = nil
        }
    }
}
