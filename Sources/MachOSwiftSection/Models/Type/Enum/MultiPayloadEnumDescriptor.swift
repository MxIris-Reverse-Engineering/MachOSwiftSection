import MachOKit
import MachOFoundation

public struct MultiPayloadEnumDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let typeName: RelativeDirectPointer<MangledName>
        /// let contents: [UInt32]
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
        guard usesPayloadSpareBits else { return [] }
        return try machO.readElements(offset: offset + MemoryLayout<RelativeOffset>.size + MemoryLayout<UInt32>.size * payloadSpareBitsIndex, numberOfElements: payloadSpareBitMaskByteCount(in: machO).cast())
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

    public func typeName() throws -> MangledName {
        return try layout.typeName.resolve(from: asPointer)
    }

    public func contents() throws -> [UInt32] {
        return try pointer(of: \.sizeFlags).readElements(numberOfElements: contentsSizeInWord.cast())
    }

    public func payloadSpareBits() throws -> [UInt8] {
        guard usesPayloadSpareBits else { return [] }
        return try asPointer.readElements(offset: MemoryLayout<RelativeOffset>.size + MemoryLayout<UInt32>.size * payloadSpareBitsIndex, numberOfElements: payloadSpareBitMaskByteCount().cast())
    }

    public func payloadSpareBitMaskByteOffset() throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents()[payloadSpareBitMaskByteCountIndex] >> 16
        } else {
            return 0
        }
    }

    public func payloadSpareBitMaskByteCount() throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents()[payloadSpareBitMaskByteCountIndex] & 0xFFFF
        } else {
            return 0
        }
    }

    /*@inlinable*/
    public var contentsSizeInWord: UInt32 {
        layout.sizeFlags >> 16
    }

    /*@inlinable*/
    public var flags: UInt32 {
        layout.sizeFlags & 0xFFFF
    }

    /*@inlinable*/
    public var usesPayloadSpareBits: Bool {
        flags & 1 != 0
    }

    /*@inlinable*/
    public var sizeFlagsIndex: Int {
        0
    }

    /*@inlinable*/
    public var payloadSpareBitMaskByteCountIndex: Int {
        sizeFlagsIndex + 1
    }

    /*@inlinable*/
    public var payloadSpareBitsIndex: Int {
        let payloadSpareBitMaskByteCountFieldSize = usesPayloadSpareBits ? 1 : 0
        return payloadSpareBitMaskByteCountIndex + payloadSpareBitMaskByteCountFieldSize
    }
}

extension MultiPayloadEnumDescriptor: TopLevelDescriptor {
    public var actualSize: Int {
        MemoryLayout<RelativeDirectPointer<String>>.size + (contentsSizeInWord.cast() * MemoryLayout<UInt32>.size)
    }
}
