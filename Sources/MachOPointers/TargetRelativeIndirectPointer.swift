import MachOReading
import MachOResolving
import MachOExtensions

public struct TargetRelativeIndirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger & Sendable, IndirectType: RelativeIndirectType>: RelativeIndirectPointerProtocol where Pointee == IndirectType.Resolved {
    public typealias Element = Pointee
    public let relativeOffset: Offset

    public init(relativeOffset: Offset) {
        self.relativeOffset = relativeOffset
    }
}
