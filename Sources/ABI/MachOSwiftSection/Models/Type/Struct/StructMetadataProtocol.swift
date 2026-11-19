import MachOKit
import MachOBase

public protocol StructMetadataProtocol: ValueMetadataProtocol where Layout: StructMetadataLayout {}

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
