import MachOKit
import MachOBase

public protocol StructMetadataProtocol: ValueMetadataProtocol where Layout: StructMetadataLayout {}

extension StructMetadataProtocol {
    
    public func structDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> StructDescriptor {
        try descriptor(in: machO).struct!
    }
    
    public func structDescriptor() throws -> StructDescriptor {
        try descriptor().struct!
    }
    
    public func fieldOffsets(for descriptor: StructDescriptor? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [UInt32] {
        let descriptor = try descriptor ?? structDescriptor(in: machO)
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        let offset = offset + (descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size)
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }

    public func fieldOffsets(for descriptor: StructDescriptor? = nil) throws -> [UInt32] {
        let descriptor = try descriptor ?? structDescriptor()
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        return try asPointer.advanced(by: descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size).readElements(numberOfElements: descriptor.numFields.cast())
    }
}

// MARK: - ReadingContext Support

extension StructMetadataProtocol {
    public func structDescriptor(in context: some ReadingContext) throws -> StructDescriptor {
        try descriptor(in: context).struct!
    }

    public func fieldOffsets(for descriptor: StructDescriptor? = nil, in context: some ReadingContext) throws -> [UInt32] {
        let descriptor = try descriptor ?? structDescriptor(in: context)
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        let offset = offset + (descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size)
        return try context.readElements(at: try context.addressFromOffset(offset), numberOfElements: descriptor.numFields.cast())
    }
}
