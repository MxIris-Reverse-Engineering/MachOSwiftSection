import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct MultiPayloadEnumDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        /// let contents: [UInt32]
        public let sizeFlags: UInt32
        // .....
    }
}

extension MultiPayloadEnumDescriptor {
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

// MARK: - ReadingContext Support

extension MultiPayloadEnumDescriptor {
    public func mangledTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset), in: context)
    }

    public func contents(in context: some ReadingContext) throws -> [UInt32] {
        return try context.readElements(at: try context.addressFromOffset(offset(of: \.sizeFlags)), numberOfElements: contentsSizeInWord.cast())
    }

    public func payloadSpareBits(in context: some ReadingContext) throws -> [UInt8] {
        guard usesPayloadSpareBits else { return [] }
        return try context.readElements(at: try context.addressFromOffset(offset + MemoryLayout<RelativeOffset>.size + MemoryLayout<UInt32>.size * payloadSpareBitsIndex), numberOfElements: payloadSpareBitMaskByteCount(in: context).cast())
    }

    public func payloadSpareBitMaskByteOffset(in context: some ReadingContext) throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents(in: context)[payloadSpareBitMaskByteCountIndex] >> 16
        } else {
            return 0
        }
    }

    public func payloadSpareBitMaskByteCount(in context: some ReadingContext) throws -> UInt32 {
        if usesPayloadSpareBits {
            return try contents(in: context)[payloadSpareBitMaskByteCountIndex] & 0xFFFF
        } else {
            return 0
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MultiPayloadEnumDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: machO.context).")
    public func mangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: contents(in: machO.context).")
    public func contents(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [UInt32] {
        try contents(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBits(in: machO.context).")
    public func payloadSpareBits(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [UInt8] {
        try payloadSpareBits(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBitMaskByteOffset(in: machO.context).")
    public func payloadSpareBitMaskByteOffset(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> UInt32 {
        try payloadSpareBitMaskByteOffset(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBitMaskByteCount(in: machO.context).")
    public func payloadSpareBitMaskByteCount(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> UInt32 {
        try payloadSpareBitMaskByteCount(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: .inProcess).")
    public func mangledTypeName() throws -> MangledName {
        try mangledTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: contents(in: .inProcess).")
    public func contents() throws -> [UInt32] {
        try contents(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBits(in: .inProcess).")
    public func payloadSpareBits() throws -> [UInt8] {
        try payloadSpareBits(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBitMaskByteOffset(in: .inProcess).")
    public func payloadSpareBitMaskByteOffset() throws -> UInt32 {
        try payloadSpareBitMaskByteOffset(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: payloadSpareBitMaskByteCount(in: .inProcess).")
    public func payloadSpareBitMaskByteCount() throws -> UInt32 {
        try payloadSpareBitMaskByteCount(in: InProcessContext.shared)
    }
}
