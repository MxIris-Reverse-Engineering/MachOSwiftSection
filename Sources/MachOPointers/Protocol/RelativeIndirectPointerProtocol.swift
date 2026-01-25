import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectPointerProtocol<Pointee>: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee

    func resolveIndirectOffset<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    // MARK: - MachO
    public func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirect(from: offset, in: machO)
    }

    func resolveIndirect<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirectType(from: offset, in: machO).resolve(in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectAny(from: offset, in: machO)
    }

    func resolveIndirectAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectType(from: offset, in: machO).resolveAny(in: machO)
    }

    public func resolveIndirectType<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> IndirectType {
        return try .resolve(from: resolveDirectOffset(from: offset), in: machO)
    }

    public func resolveIndirectOffset<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Int {
        return try resolveIndirectType(from: offset, in: machO).resolveOffset(in: machO)
    }
    
    // MARK: - InProcess
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
    
    // MARK: - Context
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirect(at: address, in: context)
    }

    func resolveIndirect<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirectType(at: address, in: context).resolve(in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectAny(at: address, in: context)
    }

    func resolveIndirectAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectType(at: address, in: context).resolveAny(in: context)
    }

    public func resolveIndirectType<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> IndirectType {
        return try .resolve(at: resolveDirectOffset(at: address, in: context), in: context)
    }

    public func resolveIndirectOffset<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        return try resolveIndirectType(at: address, in: context).resolveAddress(in: context)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
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
