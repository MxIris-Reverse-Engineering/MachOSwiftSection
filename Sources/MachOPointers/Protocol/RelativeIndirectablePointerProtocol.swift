import MachOKit

import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectablePointerProtocol<Pointee>: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var relativeOffsetPlusIndirect: Offset { get }
    var isIndirect: Bool { get }
    func resolveIndirectableOffset<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Int
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
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        return try resolveIndirectable(from: offset, in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
        return try resolveIndirectableAny(from: offset, in: machO)
    }

    func resolveIndirectable<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: offset, in: machO)
        } else {
            return try resolveDirect(from: offset, in: machO)
        }
    }

    public func resolveIndirectableType<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: offset, in: machO)
    }

    func resolveIndirectableAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(from: offset, in: machO)
        } else {
            return try resolveDirectAny(from: offset, in: machO)
        }
    }

    public func resolveIndirectableOffset<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: offset, in: machO) else { return resolveDirectOffset(from: offset) }
        return indirectType.resolveOffset(in: machO)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: offset, in: machO)
    }
}
