import MachOFoundation

public struct TargetRelativeDirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger>: RelativeDirectPointerProtocol {
    public typealias Element = Pointee
    public let relativeOffset: Offset
}
