import MachOKit
import MachOReading
import MachOExtensions
import MachOResolving

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointerProtocol {}

extension RelativeDirectPointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveDirect(from: offset, in: machO)
    }

    func resolveDirect<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectOffset(from: offset), in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveDirectAny(from: offset, in: machO)
    }

    func resolveDirectAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        return try T.resolve(from: resolveDirectOffset(from: offset), in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        return try resolveDirect(from: ptr)
    }

    func resolveDirect(from ptr: UnsafeRawPointer) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectOffset(from: ptr))
    }

    public func resolveAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        return try resolveDirectAny(from: ptr)
    }

    func resolveDirectAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        return try T.resolve(from: resolveDirectOffset(from: ptr))
    }
    
    public func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Pointee {
        return try resolveDirect(at: address, in: context)
    }

    func resolveDirect<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Pointee {
        return try Pointee.resolve(at: resolveDirectOffset(at: address, in: context), in: context)
    }
    
    public func resolveAny<T: Resolvable, Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> T {
        return try resolveDirectAny(at: address, in: context)
    }
    
    func resolveDirectAny<T: Resolvable, Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> T {
        return try T.resolve(at: resolveDirectOffset(at: address, in: context), in: context)
    }
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: offset, in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: ptr)
    }
    
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(at: address, in: context)
    }
}
