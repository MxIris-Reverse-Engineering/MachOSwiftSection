import MachOKit
import MachOReading
import MachOExtensions

public protocol RelativeIndirectablePointerIntPairProtocol<Pointee>: RelativeIndirectablePointerProtocol {
    typealias Integer = Value.RawValue
    associatedtype Value: RawRepresentable where Value.RawValue: FixedWidthInteger
    var relativeOffsetPlusIndirectAndInt: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativeIndirectablePointerIntPairProtocol {
    public var relativeOffsetPlusIndirect: Offset {
        relativeOffsetPlusIndirectAndInt & ~mask
    }

    public var relativeOffset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast((relativeOffsetPlusIndirectAndInt & mask) >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}

extension RelativeIndirectablePointerIntPairProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: offset, in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: ptr)
    }
}
