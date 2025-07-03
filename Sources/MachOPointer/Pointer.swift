import MachOKit
import MachOReading
import MachOExtensions

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee
    
    public let address: UInt64

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machO: MachO) throws -> Self {
        if let machOFile = machO as? MachOFile, let rebase = machOFile.resolveRebase(fileOffset: fileOffset.cast()) {
            return .init(address: rebase)
        } else {
            return try machO.readElement(offset: fileOffset)
        }
    }
    
    public init(address: UInt64) {
        self.address = address
    }
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>

public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
