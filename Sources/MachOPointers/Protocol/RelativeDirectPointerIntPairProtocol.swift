import MachOKit
import MachOReading
import MachOExtensions

public protocol RelativeDirectPointerIntPairProtocol<Pointee>: RelativeDirectPointerProtocol {
    typealias Integer = Value.RawValue
    associatedtype Value: RawRepresentable where Value.RawValue: FixedWidthInteger
    var relativeOffsetPlusInt: Offset { get }
}

extension RelativeDirectPointerIntPairProtocol {
    public var relativeOffset: Offset {
        relativeOffsetPlusInt & ~mask
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1)
    }

    public var intValue: Integer {
        numericCast(relativeOffsetPlusInt & mask)
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}
