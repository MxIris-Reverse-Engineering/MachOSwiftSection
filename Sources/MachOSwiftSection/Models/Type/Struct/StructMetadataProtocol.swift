import MachOKit
import MachOFoundation

public protocol StructMetadataProtocol: MetadataProtocol where Layout: StructMetadataLayout {}

extension StructMetadataProtocol {
    public func fieldOffsets<MachO: MachOSwiftSectionRepresentableWithCache>(for descriptor: StructDescriptor? = nil, in machO: MachO) throws -> [UInt32] {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO)
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        let offset = offset + (descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size)
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }

    public func fieldOffsets(for descriptor: StructDescriptor? = nil) throws -> [UInt32] {
        let descriptor = try descriptor ?? layout.descriptor.resolve()
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        // Metadata.offset + fieldOffset (eg. 2 * 8)
        return try asPointer.advanced(by: descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredSize>.size).readElements(numberOfElements: descriptor.numFields.cast())
    }
}
