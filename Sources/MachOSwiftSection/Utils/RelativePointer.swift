import Foundation
@_spi(Support) import MachOKit

public typealias RelativeOffset = Int32

public protocol RelativePointer {
    associatedtype Pointee
    associatedtype Offset: FixedWidthInteger
    var offset: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativePointer where Pointee == String? {
    public func resolve(from address: UInt64, in machO: MachOFile) -> Pointee? {
        return machO.fileHandle.readString(offset: resolveAddress(from: address, in: machO) + machO.headerStartOffset.cast())
    }
}

extension RelativePointer where Pointee == String {
    public func resolve(from address: UInt64, in machO: MachOFile) -> Pointee {
        return machO.fileHandle.readString(offset: resolveAddress(from: address, in: machO) + machO.headerStartOffset.cast())!
    }
}

extension RelativePointer where Pointee: LayoutWrapperWithOffset {
    public func resolve(from address: UInt64, in machO: MachOFile) -> Pointee {
        let resolveOffset = resolveAddress(from: address, in: machO)
        let layout: Pointee.Layout = machO.fileHandle.read(offset: resolveOffset + machO.headerStartOffset.cast())
        return .init(offset: resolveOffset.cast(), layout: layout)
    }
}

extension RelativePointer {
    public func resolve(from address: UInt64, in machO: MachOFile) -> Pointee {
        return machO.fileHandle.read(offset: resolveAddress(from: address, in: machO) + machO.headerStartOffset.cast())
    }

    public func resolveAddress(from address: UInt64, in machO: MachOFile) -> UInt64 {
        let resolvedAddress = Int(address) + Int(offset)

        if isIndirect {
            return machO.fileOffset(of: machO.fileHandle.read(offset: numericCast(resolvedAddress + machO.headerStartOffset)))
        } else {
            return resolvedAddress.cast()
        }
    }

    public var isDirect: Bool {
        return !isIndirect
    }

    public var isNull: Bool {
        return offset == 0
    }

    public var isValid: Bool {
        return offset != 0
    }
}

public typealias RelativeDirectPointer<Pointee> = TargetRelativeDirectPointer<Pointee, RelativeOffset>
public typealias RelativeIndirectPointer<Pointee> = TargetRelativeIndirectPointer<Pointee, RelativeOffset>
public typealias RelativeIndirectablePointer<Pointee> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset>
public typealias RelativeIndirectablePointerIntPair<Pointee, Integer: FixedWidthInteger> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer>

public struct TargetRelativeDirectPointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let offset: Offset
    public var isIndirect: Bool { false }
}

public struct TargetRelativeIndirectPointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let offset: Offset
    public var isIndirect: Bool { true }
}

public struct TargetRelativeIndirectablePointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let relativeOffsetPlusIndirect: Offset
    public var offset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }

    public func withIntPairPointer<Integer: FixedWidthInteger>(_ integer: Integer.Type = Integer.self) -> TargetRelativeIndirectablePointerIntPair<Pointee, Offset, Integer> {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }

    public func withValuePointer<Value: RawRepresentable>(_ integer: Value.Type = Value.self) -> TargetRelativeIndirectablePointerWithValue<Pointee, Offset, Value> where Value.RawValue: FixedWidthInteger {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }
}

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger, Integer: FixedWidthInteger>: RelativePointer {
    public let relativeOffsetPlusIndirectAndInt: Offset

    public var offset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast(relativeOffsetPlusIndirectAndInt & mask >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }
}

public struct TargetRelativeIndirectablePointerWithValue<Pointee, Offset: FixedWidthInteger, Value: RawRepresentable>: RelativePointer where Value.RawValue: FixedWidthInteger {
    public typealias Integer = Value.RawValue

    public let relativeOffsetPlusIndirectAndInt: Offset

    public var offset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast(relativeOffsetPlusIndirectAndInt & mask >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}
