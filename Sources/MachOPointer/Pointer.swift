import MachOKit
import MachOReading
import MachOExtensions

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee

    public let address: UInt64

    public init(address: UInt64) {
        self.address = address
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        if let machOFile = machO as? MachOFile, let rebase = machOFile.resolveRebase(fileOffset: offset.cast()) {
            return .init(address: rebase)
        } else {
            return try machO.readElement(offset: offset)
        }
    }
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>

public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
