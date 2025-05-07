//
//  TargetRelativeIndirectablePointerIntPair.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger, Integer: FixedWidthInteger, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Pointee == IndirectType.Pointee {
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
}