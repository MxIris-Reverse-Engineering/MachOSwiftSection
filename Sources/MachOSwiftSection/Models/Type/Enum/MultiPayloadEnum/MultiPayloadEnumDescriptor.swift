import MachOKit
import MachOFoundation

public struct MultiPayloadEnumDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let typeName: RelativeDirectPointer<MangledName>
        // let contents: [UInt32]
        public let sizeFlags: UInt32
        // .....
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MultiPayloadEnumDescriptor {
    public func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        return try layout.typeName.resolve(from: offset, in: machO)
    }

    public func contents(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [UInt32] {
        return try machO.readElements(offset: offset(of: \.sizeFlags), numberOfElements: contentsSizeInWord.cast())
    }

    public func payloadSpareBits(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [UInt8] {
        return try machO.readElements(offset: MemoryLayout<RelativeOffset>.size + MemoryLayout<UInt32>.size * payloadSpareBitsIndex, numberOfElements: payloadSpareBitMaskByteCount(in: machO).cast())
    }
    
    public var contentsSizeInWord: UInt32 {
        layout.sizeFlags >> 16
    }
    
    public var flags: UInt32 {
        layout.sizeFlags & 0xFFFF
    }
    
    public var usesPayloadSpareBits: Bool {
        flags & 1 != 0
    }
    
    public var sizeFlagsIndex: Int {
        0
    }
    
    public var payloadSpareBitMaskByteCountIndex: Int {
        sizeFlagsIndex + 1
    }
    
    public var payloadSpareBitsIndex: Int {
        let payloadSpareBitMaskByteCountFieldSize = usesPayloadSpareBits ? 1 : 0
        return payloadSpareBitMaskByteCountIndex + payloadSpareBitMaskByteCountFieldSize
    }
    
    public func payloadSpareBitMaskByteOffset(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents(in: machO)[payloadSpareBitMaskByteCountIndex] >> 16
        } else {
            return 0
        }
    }
    
    public func payloadSpareBitMaskByteCount(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents(in: machO)[payloadSpareBitMaskByteCountIndex] & 0xFFFF
        } else {
            return 0
        }
    }
}

extension MultiPayloadEnumDescriptor: TopLevelDescriptor {
    public var actualSize: Int {
        MemoryLayout<RelativeDirectPointer<String>>.size + (contentsSizeInWord.cast() * MemoryLayout<UInt32>.size)
    }
}
