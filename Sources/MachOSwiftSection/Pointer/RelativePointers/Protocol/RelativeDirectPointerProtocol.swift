import MachOKit
import MachOSwiftSectionMacro

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

//extension RelativeDirectPointerProtocol {
//    public func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
//        return try resolveDirect(from: imageOffset, in: machOImage)
//    }
//    
//    func resolveDirect(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
//        return try Pointee.resolve(from: resolveDirectOffset(from: imageOffset), in: machOImage)
//    }
//    
//    public func resolveAny<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
//        return try resolveDirect(from: imageOffset, in: machOImage)
//    }
//
//    func resolveDirect<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
//        return try machOImage.assumingElement(offset: resolveDirectOffset(from: imageOffset))
//    }
//}

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
