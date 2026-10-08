import Foundation
import MachOKit
import MachOBase

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
}

// MARK: - ReadingContext Support

extension Struct {
    public init(descriptor: StructDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.typeGenericContext(in: context)

        if let genericContext {
            currentOffset += genericContext.size
        }

        self.genericContext = genericContext

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: context)
    }

    private mutating func initialize(descriptor: StructDescriptor, currentOffset: inout Int, in context: some ReadingContext) throws {
        let typeFlags = try required(descriptor.flags.kindSpecificFlags?.typeFlags)

        if typeFlags.hasForeignMetadataInitialization {
            foreignMetadataInitialization = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset)) as ForeignMetadataInitialization
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            foreignMetadataInitialization = nil
        }

        if typeFlags.hasSingletonMetadataInitialization {
            singletonMetadataInitialization = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset)) as SingletonMetadataInitialization
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            singletonMetadataInitialization = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try context.readElement(at: try context.addressFromOffset(currentOffset))
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalMetadataPrespecializations: [CanonicalSpecializedMetadatasListEntry] = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            canonicalSpecializedMetadatas = canonicalMetadataPrespecializations
            canonicalSpecializedMetadatasListCount = count
            canonicalSpecializedMetadatasCachingOnceToken = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset)) as CanonicalSpecializedMetadatasCachingOnceToken
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            canonicalSpecializedMetadatas = []
            canonicalSpecializedMetadatasListCount = nil
            canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.hasInvertibleProtocols {
            invertibleProtocolSet = try context.readElement(at: try context.addressFromOffset(currentOffset)) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            singletonMetadataPointer = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset)) as SingletonMetadataPointer
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            singletonMetadataPointer = nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension Struct {
    @available(*, deprecated, message: "Pass a ReadingContext: Struct(descriptor:in: machO.context).")
    public init(descriptor: StructDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: Struct(descriptor:in: .inProcess).")
    public init(descriptor: StructDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
