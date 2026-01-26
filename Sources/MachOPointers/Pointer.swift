import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee

    public let address: UInt64

    public init(address: UInt64) {
        self.address = address
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        if let machOFile = machO as? MachOFile, let rebase = machOFile.resolveRebase(fileOffset: offset.cast()) {
            return .init(address: rebase)
        } else {
            return try machO.readElement(offset: offset)
        }
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        .init(address: ptr.assumingMemoryBound(to: UInt64.self).pointee)
    }

    public static func resolve<Context>(at address: Context.Address, in context: Context) throws -> Pointer<Pointee> where Context : ReadingContext {
        return try context.readElement(at: address)
    }
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>

public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
