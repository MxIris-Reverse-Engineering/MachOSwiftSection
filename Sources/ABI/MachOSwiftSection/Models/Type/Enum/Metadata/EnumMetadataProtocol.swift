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
        return try context.readElement(at: try context.addressFromOffset(offset))
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension EnumMetadataProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: enumDescriptor(in: machO.context).")
    public func enumDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> EnumDescriptor {
        try enumDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSize(in: machO.context).")
    public func payloadSize(descriptor: EnumDescriptor? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> StoredSize? {
        try payloadSize(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: enumDescriptor(in: .inProcess).")
    public func enumDescriptor() throws -> EnumDescriptor {
        try enumDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSize(in: .inProcess).")
    public func payloadSize(descriptor: EnumDescriptor? = nil) throws -> StoredSize? {
        try payloadSize(descriptor: descriptor, in: InProcessContext.shared)
    }
}
