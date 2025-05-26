import MachOKit
import MachOSwiftSectionMacro

public protocol RelativeIndirectPointerProtocol: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee
    
    func resolveIndirectOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int
    
    func resolveIndirectOffset(from imageOffset: Int, in machOImage: MachOImage) throws -> Int
}

@MachOImageAllMembersGenerator
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
        return try .resolve(from: resolveDirectOffset(from: fileOffset), in: machOFile)
    }

    public func resolveIndirectOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveOffset(in: machOFile)
    }
}

//extension RelativeIndirectPointerProtocol {
//    public func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
//        return try resolveIndirect(from: imageOffset, in: machOImage)
//    }
//
//    func resolveIndirect(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee {
//        return try resolveIndirectType(from: imageOffset, in: machOImage).resolve(in: machOImage)
//    }
//
//    public func resolveAny<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
//        return try resolveIndirect(from: imageOffset, in: machOImage)
//    }
//
//    func resolveIndirect<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T {
//        return try resolveIndirectType(from: imageOffset, in: machOImage).resolveAny(in: machOImage)
//    }
//
//    func resolveIndirectType(from imageOffset: Int, in machOImage: MachOImage) throws -> IndirectType {
//        return try .resolve(from: resolveDirectOffset(from: imageOffset), in: machOImage)
//    }
//
//    public func resolveIndirectOffset(from imageOffset: Int, in machOImage: MachOImage) throws -> Int {
//        return try resolveIndirectType(from: imageOffset, in: machOImage).resolveOffset(in: machOImage)
//    }
//}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOImage) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
