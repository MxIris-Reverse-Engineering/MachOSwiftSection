import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public struct Pointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
    public typealias Resolved = Pointee

    public let address: UInt64

    public init(address: UInt64) {
        self.address = address
    }

    /// Reads the pointer stored at `address`. In a file the stored bytes of a
    /// rebased slot are a chained-fixup encoding, not an address; the rebase
    /// table says what dyld writes there at load time.
    public static func resolve<Context>(at address: Context.Address, in context: Context) throws -> Pointer<Pointee> where Context : ReadingContext {
        if let resolver = context.bindRebaseResolver, let rebase = resolver.resolveRebase(fileOffset: try context.offsetFromAddress(address)) {
            return .init(address: rebase)
        }
        return try context.readElement(at: address)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

public typealias RawPointer = Pointer<AnyResolvable>

public typealias MetadataPointer<Pointee: Resolvable> = Pointer<Pointee>

public typealias ConstMetadataPointer<Pointee: Resolvable> = MetadataPointer<Pointee>
