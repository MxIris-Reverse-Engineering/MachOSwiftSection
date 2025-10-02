import Foundation
import MachOKit
import MachOFoundation

public protocol ClassMetadataProtocol: HeapMetadataProtocol {}

public protocol ClassMetadataLayoutWithDescriptor {
    var descriptor: Pointer<ClassDescriptor> { get }
}

extension ClassMetadataProtocol where Layout: ClassMetadataLayoutWithDescriptor {
    public func fieldOffsets<MachO: MachOSwiftSectionRepresentableWithCache>(for descriptor: ClassDescriptor? = nil, in machO: MachO) throws -> [StoredPointer] {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO)
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = offset.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }
}
