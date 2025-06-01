import MachOKit
import MachOMacro
import MachOFoundation

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointerProtocol {}

@MachOImageAllMembersGenerator
extension RelativeDirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveDirect(from: fileOffset, in: machOFile)
    }

    func resolveDirect(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectOffset(from: fileOffset), in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveDirect(from: fileOffset, in: machOFile)
    }

    func resolveDirect<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try machOFile.readElement(offset: resolveDirectOffset(from: fileOffset))
    }
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: imageOffset, in: machOImage)
    }
}
