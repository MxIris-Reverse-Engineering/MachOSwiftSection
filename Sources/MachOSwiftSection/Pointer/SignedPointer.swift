import MachOKit

public struct SignedPointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public let address: UInt64
}
