import MachOKit
import MachOBase

public protocol EnumMetadataProtocol: ValueMetadataProtocol where Layout: EnumMetadataLayout {}

// MARK: - ReadingContext Support

extension EnumMetadataProtocol {
    public func enumDescriptor(in context: some ReadingContext) throws -> EnumDescriptor {
        try descriptor(in: context).enum!
    }

    public func payloadSize(descriptor: EnumDescriptor? = nil, in context: some ReadingContext) throws -> StoredSize? {
        let descriptor = try descriptor ?? enumDescriptor(in: context)
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        // Annotated: asking for the optional directly would read the
        // Optional's in-memory shape, one tag byte past the size word.
        let payloadSize: StoredSize = try context.readElement(at: try context.addressFromOffset(offset))
        return payloadSize
    }
}
