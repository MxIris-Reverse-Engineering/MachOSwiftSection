import MachOKit
import MachOFoundation

public protocol EnumMetadataProtocol: MetadataProtocol where Layout: EnumMetadataLayout {}

extension EnumMetadataProtocol {
    public func payloadSize<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: EnumDescriptor? = nil, in machO: MachO) throws -> StoredSize? {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO)
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try machO.readElement(offset: offset)
    }
    
    public func payloadSize(descriptor: EnumDescriptor? = nil) throws -> StoredSize? {
        let descriptor = try descriptor ?? layout.descriptor.resolve()
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = Int.zero.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try asPointer.readElement(offset: offset)
    }
}
