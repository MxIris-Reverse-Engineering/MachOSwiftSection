public struct TargetRelativeIndirectablePointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Pointee == IndirectType.Resolved {
    public let relativeOffsetPlusIndirect: Offset

    public func withIntPairPointer<Integer: FixedWidthInteger>(_ integer: Integer.Type = Integer.self) -> TargetRelativeIndirectablePointerIntPair<Pointee, Offset, Integer, IndirectType> {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }
}
