import MachOKit

public protocol RelativeIndirectPointerProtocol: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee
    func resolveIndirectFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirect(from: fileOffset, in: machOFile)
    }

    func resolveIndirect(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolve(in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirect(from: fileOffset, in: machOFile)
    }

    func resolveIndirect<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveAny(in: machOFile)
    }

    func resolveIndirectType(from fileOffset: Int, in machOFile: MachOFile) throws -> IndirectType {
        return try .resolve(from: resolveDirectFileOffset(from: fileOffset), in: machOFile)
    }

    public func resolveIndirectFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
