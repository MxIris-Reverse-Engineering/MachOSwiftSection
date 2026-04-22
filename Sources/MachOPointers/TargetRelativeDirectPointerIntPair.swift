import MachOReading
import MachOResolving
import MachOExtensions

public struct TargetRelativeDirectPointerIntPair<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger & Sendable, Value: RawRepresentable>: RelativeDirectPointerIntPairProtocol where Value.RawValue: FixedWidthInteger {
    public let relativeOffsetPlusInt: Offset

    public init(relativeOffsetPlusInt: Offset) {
        self.relativeOffsetPlusInt = relativeOffsetPlusInt
    }
}
