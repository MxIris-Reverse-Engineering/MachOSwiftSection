import Foundation
import MachOKit
import MachOBase

public protocol FinalClassMetadataProtocol: HeapMetadataProtocol {}

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
