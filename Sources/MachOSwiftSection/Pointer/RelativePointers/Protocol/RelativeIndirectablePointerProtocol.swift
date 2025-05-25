import MachOKit

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

extension RelativeIndirectablePointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machOFile)
    }

    func resolveIndirectable(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    func resolveIndirectableType(from fileOffset: Int, in machOFile: MachOFile) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machOFile)
    }

    func resolveIndirectableAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
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

extension RelativeIndirectablePointerProtocol {
    public func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
        return try resolveIndirectable(from: imageOffset, in: machOImage)
    }

    public func resolveAny<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
        return try resolveIndirectableAny(from: imageOffset, in: machOImage)
    }

    func resolveIndirectable(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: imageOffset, in: machOImage)
        } else {
            return try resolveDirect(from: imageOffset, in: machOImage)
        }
    }

    func resolveIndirectableType(from imageOffset: Int, in machOImage: MachOImage) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: imageOffset, in: machOImage)
    }

    func resolveIndirectableAny<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
        if isIndirect {
            return try resolveIndirect(from: imageOffset, in: machOImage)
        } else {
            return try resolveDirect(from: imageOffset, in: machOImage)
        }
    }

    public func resolveIndirectableOffset(from imageOffset: Int, in machOImage: MachOImage) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: imageOffset, in: machOImage) else { return resolveDirectOffset(from: imageOffset) }
        return indirectType.resolveOffset(in: machOImage)
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

