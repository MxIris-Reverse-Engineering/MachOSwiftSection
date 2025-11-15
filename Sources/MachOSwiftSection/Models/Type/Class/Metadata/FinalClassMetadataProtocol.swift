import Foundation
import MachOKit
import MachOFoundation

public protocol FinalClassMetadataProtocol: HeapMetadataProtocol {}

extension FinalClassMetadataProtocol where Layout: FinalClassMetadataLayout {
    public func fieldOffsets<MachO: MachOSwiftSectionRepresentableWithCache>(for descriptor: ClassDescriptor? = nil, in machO: MachO) throws -> [StoredPointer] {
        guard let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO) else { return [] }
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = offset.offseting(of: StoredPointer.self, numbersOfElements: descriptor.fieldOffsetVectorOffset.cast())
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }

    public func descriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ClassDescriptor? {
        try layout.descriptor.resolve(in: machO)
    }
}
