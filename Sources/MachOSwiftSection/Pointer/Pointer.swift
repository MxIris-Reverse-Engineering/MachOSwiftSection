import MachOKit
import MachOFoundation

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee
    
    public let address: UInt64

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        if let rebase = machOFile.resolveRebase(fileOffset: fileOffset.cast()) {
            return .init(address: rebase)
        } else {
            return try machOFile.readElement(offset: fileOffset)
        }
    }
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>

public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
