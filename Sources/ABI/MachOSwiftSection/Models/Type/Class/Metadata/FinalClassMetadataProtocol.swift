import Foundation
import MachOKit
import MachOBase

public protocol FinalClassMetadataProtocol: HeapMetadataProtocol {}

extension FinalClassMetadataProtocol where Layout: FinalClassMetadataLayout {
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [StoredPointer] {
        guard let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO) else { return [] }
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = offset.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }

    public func fieldOffsets(for descriptor: ClassDescriptor? = nil) throws -> [StoredPointer] {
        guard let descriptor = try descriptor ?? layout.descriptor.resolve() else { return [] }
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = Int.zero.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try asPointer.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }
    
    public func descriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        try layout.descriptor.resolve(in: machO)
    }

    public func descriptor() throws -> ClassDescriptor? {
        try layout.descriptor.resolve()
    }
}

// MARK: - ReadingContext Support

extension FinalClassMetadataProtocol where Layout: FinalClassMetadataLayout {
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil, in context: some ReadingContext) throws -> [StoredPointer] {
        guard let descriptor = try descriptor ?? layout.descriptor.resolve(in: context) else { return [] }
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let fieldOffsetsOffset = offset.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try context.readElements(at: try context.addressFromOffset(fieldOffsetsOffset), numberOfElements: descriptor.numFields.cast())
    }

    public func descriptor(in context: some ReadingContext) throws -> ClassDescriptor? {
        try layout.descriptor.resolve(in: context)
    }
}
