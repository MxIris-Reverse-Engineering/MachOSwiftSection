import MachOKit
import MachOFoundation

public protocol EnumMetadataProtocol: ValueMetadataProtocol where Layout: EnumMetadataLayout {}

extension EnumMetadataProtocol {
    public func enumDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> EnumDescriptor {
        try layout.descriptor.resolve(in: machO).enum!
    }

    public func enumDescriptor() throws -> EnumDescriptor {
        try layout.descriptor.resolve().enum!
    }

    public func payloadSize<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: EnumDescriptor? = nil, in machO: MachO) throws -> StoredSize? {
        let descriptor = try descriptor ?? enumDescriptor(in: machO)
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try machO.readElement(offset: offset)
    }

    public func payloadSize(descriptor: EnumDescriptor? = nil) throws -> StoredSize? {
        let descriptor = try descriptor ?? enumDescriptor()
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = Int.zero.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try asPointer.readElement(offset: offset)
    }
}

// MARK: - ReadingContext Support

extension EnumMetadataProtocol {
    public func enumDescriptor<Context: ReadingContext>(in context: Context) throws -> EnumDescriptor {
        try layout.descriptor.resolve(in: context).enum!
    }

    public func payloadSize<Context: ReadingContext>(descriptor: EnumDescriptor? = nil, in context: Context) throws -> StoredSize? {
        let descriptor = try descriptor ?? enumDescriptor(in: context)
        guard descriptor.hasPayloadSizeOffset else {
            return nil
        }
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try context.readElement(at: try context.addressFromOffset(offset))
    }
}
