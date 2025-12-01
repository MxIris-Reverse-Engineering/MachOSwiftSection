import MachOKit
import MachOReading
import MachOExtensions
import MachOResolving

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointerProtocol {}

extension RelativeDirectPointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveDirect(from: offset, in: machO)
    }

    func resolveDirect<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectOffset(from: offset), in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveDirectAny(from: offset, in: machO)
    }

    func resolveDirectAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
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
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: offset, in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: ptr)
    }
}
