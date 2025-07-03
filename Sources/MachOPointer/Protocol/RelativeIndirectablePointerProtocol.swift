import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol RelativeIndirectablePointerProtocol: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var relativeOffsetPlusIndirect: Offset { get }
    var isIndirect: Bool { get }
    func resolveIndirectableOffset<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Int
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
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machOFile)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machOFile)
    }

    func resolveIndirectable<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    public func resolveIndirectableType<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machOFile)
    }

    func resolveIndirectableAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirectAny(from: fileOffset, in: machOFile)
        }
    }

    public func resolveIndirectableOffset<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: fileOffset, in: machOFile) else { return resolveDirectOffset(from: fileOffset) }
        return indirectType.resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
