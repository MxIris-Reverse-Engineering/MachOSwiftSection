import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectablePointerProtocol<Pointee>: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var relativeOffsetPlusIndirect: Offset { get }
    var isIndirect: Bool { get }
    func resolveIndirectableOffset<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Int
}

extension RelativeIndirectablePointerProtocol {
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }
}

extension RelativeIndirectablePointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirectable(from: offset, in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectableAny(from: offset, in: machO)
    }

    func resolveIndirectable<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: offset, in: machO)
        } else {
            return try resolveDirect(from: offset, in: machO)
        }
    }

    public func resolveIndirectableType<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectType(from: offset, in: machO)
    }

    func resolveIndirectableAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(from: offset, in: machO)
        } else {
            return try resolveDirectAny(from: offset, in: machO)
        }
    }

    public func resolveIndirectableOffset<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: offset, in: machO) else {
            return resolveDirectOffset(from: offset)
        }
        return indirectType.resolveOffset(in: machO)
    }

    // MARK: - InProcess
    
    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        return try resolveIndirectable(from: ptr)
    }

    public func resolveAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        return try resolveIndirectableAny(from: ptr)
    }

    func resolveIndirectable(from ptr: UnsafeRawPointer) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: ptr)
        } else {
            return try resolveDirect(from: ptr)
        }
    }

    public func resolveIndirectableType(from ptr: UnsafeRawPointer) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectType(from: ptr)
    }

    func resolveIndirectableAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(from: ptr)
        } else {
            return try resolveDirectAny(from: ptr)
        }
    }

    // MARK: - Context
    
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirectable(at: address, in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectableAny(at: address, in: context)
    }

    func resolveIndirectable<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(at: address, in: context)
        } else {
            return try resolveDirect(at: address, in: context)
        }
    }

    public func resolveIndirectableType<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectType(at: address, in: context)
    }

    func resolveIndirectableAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(at: address, in: context)
        } else {
            return try resolveDirectAny(at: address, in: context)
        }
    }

    public func resolveIndirectableOffset<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        guard let indirectType = try resolveIndirectableType(at: address, in: context) else {
            return try resolveDirectAddress(at: address, in: context)
        }
        return try indirectType.resolveAddress(in: context)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
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
