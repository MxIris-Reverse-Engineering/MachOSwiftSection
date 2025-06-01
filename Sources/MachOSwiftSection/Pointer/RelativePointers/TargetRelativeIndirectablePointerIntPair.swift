import MachOFoundation

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger & SignedInteger, Value: RawRepresentable, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerIntPairProtocol where Value.RawValue: FixedWidthInteger, Pointee == IndirectType.Resolved {
    public let relativeOffsetPlusIndirectAndInt: Offset
}
