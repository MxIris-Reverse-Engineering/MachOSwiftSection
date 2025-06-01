import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol RelativeIndirectablePointerProtocol: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var relativeOffsetPlusIndirect: Offset { get }
    var isIndirect: Bool { get }
    func resolveIndirectableOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int
    func resolveIndirectableOffset(from imageOffset: Int, in machOFile: MachOImage) throws -> Int
}

extension RelativeIndirectablePointerProtocol {
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }
}

@MachOImageAllMembersGenerator
extension RelativeIndirectablePointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machOFile)
    }

    public func resolveAny<T: Resolvable>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machOFile)
    }

    func resolveIndirectable(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    public func resolveIndirectableType(from fileOffset: Int, in machOFile: MachOFile) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machOFile)
    }

    func resolveIndirectableAny<T: Resolvable>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    public func resolveIndirectableOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: fileOffset, in: machOFile) else { return resolveDirectOffset(from: fileOffset) }
        return indirectType.resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOImage) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}

