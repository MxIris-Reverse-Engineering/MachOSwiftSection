import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol RelativeIndirectPointerProtocol: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee

    func resolveIndirectOffset<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        return try resolveIndirect(from: fileOffset, in: machOFile)
    }

    func resolveIndirect<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolve(in: machOFile)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        return try resolveIndirectAny(from: fileOffset, in: machOFile)
    }

    func resolveIndirectAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveAny(in: machOFile)
    }

    public func resolveIndirectType<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> IndirectType {
        return try .resolve(from: resolveDirectOffset(from: fileOffset), in: machOFile)
    }

    public func resolveIndirectOffset<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
