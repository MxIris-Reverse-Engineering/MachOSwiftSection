import MachOKit

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee
    public let address: UInt64
}

public typealias RawPointer = Pointer<AnyResolvableElement>
