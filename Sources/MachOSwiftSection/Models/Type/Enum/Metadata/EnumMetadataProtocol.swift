import MachOKit
import MachOFoundation

public protocol EnumMetadataProtocol: MetadataProtocol where Layout: EnumMetadataLayout {}

extension EnumMetadataProtocol {
    public func payloadSize<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> StoredSize? {
        let descriptor = try layout.descriptor.resolve(in: machO)
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try machO.readElement(offset: offset)
    }
}
