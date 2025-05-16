//
//  TargetRelativeIndirectablePointerIntPair.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger & SignedInteger, Value: RawRepresentable, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Value.RawValue: FixedWidthInteger, Pointee == IndirectType.Pointee {
    public typealias Integer = Value.RawValue

    public let relativeOffsetPlusIndirectAndInt: Offset

    public var relativeOffset: Offset {
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

extension Bool: @retroactive RawRepresentable {
    public var rawValue: UInt8 { self ? 1 : 0 }
    public init?(rawValue: UInt8) {
        self = rawValue != 0
    }
}
