import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectPointerProtocol<Pointee>: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee

    func resolveIndirectOffset<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirect(from: offset, in: machO)
    }

    func resolveIndirect<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirectType(from: offset, in: machO).resolve(in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectAny(from: offset, in: machO)
    }

    func resolveIndirectAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectType(from: offset, in: machO).resolveAny(in: machO)
    }

    public func resolveIndirectType<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> IndirectType {
        return try .resolve(from: resolveDirectOffset(from: offset), in: machO)
    }

    public func resolveIndirectOffset<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Int {
        return try resolveIndirectType(from: offset, in: machO).resolveOffset(in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        return try resolveIndirect(from: ptr)
    }

    func resolveIndirect(from ptr: UnsafeRawPointer) throws -> Pointee {
        return try resolveIndirectType(from: ptr).resolve()
    }

    public func resolveAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        return try resolveIndirectAny(from: ptr)
    }

    func resolveIndirectAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        return try resolveIndirectType(from: ptr).resolveAny()
    }

    public func resolveIndirectType(from ptr: UnsafeRawPointer) throws -> IndirectType {
        return try .resolve(from: resolveDirectOffset(from: ptr))
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: offset, in: machO)
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: ptr)
    }
}
