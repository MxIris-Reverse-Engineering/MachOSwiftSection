import MachOReading
import MachOExtensions

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger & SignedInteger & Sendable, Value: RawRepresentable, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerIntPairProtocol where Value.RawValue: FixedWidthInteger, Pointee == IndirectType.Resolved {
    public let relativeOffsetPlusIndirectAndInt: Offset

    public init(relativeOffsetPlusIndirectAndInt: Offset) {
        self.relativeOffsetPlusIndirectAndInt = relativeOffsetPlusIndirectAndInt
    }
}
