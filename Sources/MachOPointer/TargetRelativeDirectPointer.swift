import MachOReading
import MachOExtensions

public struct TargetRelativeDirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger>: RelativeDirectPointerProtocol {
    public typealias Element = Pointee
    public let relativeOffset: Offset
    public init(relativeOffset: Offset) {
        self.relativeOffset = relativeOffset
    }
}
