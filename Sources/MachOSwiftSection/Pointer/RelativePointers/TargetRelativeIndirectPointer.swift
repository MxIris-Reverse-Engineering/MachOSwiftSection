import MachOFoundation

public struct TargetRelativeIndirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger, IndirectType: RelativeIndirectType>: RelativeIndirectPointerProtocol where Pointee == IndirectType.Resolved {
    public typealias Element = Pointee
    public let relativeOffset: Offset
}
