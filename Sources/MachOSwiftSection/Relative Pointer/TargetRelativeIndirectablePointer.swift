//
//  TargetRelativeIndirectablePointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public struct TargetRelativeIndirectablePointer<Pointee: ResolvableElement, Offset: FixedWidthInteger & SignedInteger, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Pointee == IndirectType.Pointee {
    public typealias Element = Pointee
    public let relativeOffsetPlusIndirect: Offset
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }

    public func withIntPairPointer<Integer: FixedWidthInteger>(_ integer: Integer.Type = Integer.self) -> TargetRelativeIndirectablePointerIntPair<Pointee, Offset, Integer, IndirectType> {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }

//    public func withValuePointer<Value: RawRepresentable>(_ integer: Value.Type = Value.self) -> TargetRelativeIndirectablePointerWithValue<Pointee, Offset, Value, IndirectType> where Value.RawValue: FixedWidthInteger {
//        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
//    }
}
