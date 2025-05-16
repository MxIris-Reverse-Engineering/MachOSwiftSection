//
//  TargetRelativeIndirectablePointerIntPair.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger & SignedInteger, Value: RawRepresentable, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerIntPairProtocol where Value.RawValue: FixedWidthInteger, Pointee == IndirectType.Pointee {
    public let relativeOffsetPlusIndirectAndInt: Offset
}


