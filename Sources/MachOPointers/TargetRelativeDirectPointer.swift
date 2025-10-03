import MachOReading
import MachOResolving
import MachOExtensions

public struct TargetRelativeDirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger & Sendable>: RelativeDirectPointerProtocol {
    public typealias Element = Pointee
    public let relativeOffset: Offset
    public init(relativeOffset: Offset) {
        self.relativeOffset = relativeOffset
    }
}
