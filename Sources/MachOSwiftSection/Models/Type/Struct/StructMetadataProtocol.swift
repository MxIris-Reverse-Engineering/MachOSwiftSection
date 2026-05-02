import MachOKit
import MachOFoundation

public protocol StructMetadataProtocol: ValueMetadataProtocol where Layout: StructMetadataLayout {}

extension StructMetadataProtocol {
    
    public func structDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> StructDescriptor {
        try descriptor(in: machO).struct!
    }
    
    public func structDescriptor() throws -> StructDescriptor {
        try descriptor().struct!
    }
    
    public func fieldOffsets<MachO: MachOSwiftSectionRepresentableWithCache>(for descriptor: StructDescriptor? = nil, in machO: MachO) throws -> [UInt32] {
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
    public func structDescriptor<Context: ReadingContext>(in context: Context) throws -> StructDescriptor {
        try layout.descriptor.resolve(in: context).struct!
    }

    public func fieldOffsets<Context: ReadingContext>(for descriptor: StructDescriptor? = nil, in context: Context) throws -> [UInt32] {
        let descriptor = try descriptor ?? structDescriptor(in: context)
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        let offset = offset + (descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size)
        return try context.readElements(at: try context.addressFromOffset(offset), numberOfElements: descriptor.numFields.cast())
    }
}
