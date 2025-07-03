import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointerProtocol {}


extension RelativeDirectPointerProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        return try resolveDirect(from: fileOffset, in: machOFile)
    }

    func resolveDirect<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectOffset(from: fileOffset), in: machOFile)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        return try resolveDirectAny(from: fileOffset, in: machOFile)
    }

    func resolveDirectAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> T {
        return try T.resolve(from: resolveDirectOffset(from: fileOffset), in: machOFile)
    }
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machOFile: MachO) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
