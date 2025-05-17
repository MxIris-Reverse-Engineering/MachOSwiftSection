import MachOKit

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee
    public let address: UInt64
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>
public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
