import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol PointerProtocol: Resolvable, Sendable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve(in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T: Resolvable>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int

    func resolve(in machOImage: MachOImage) throws -> Pointee
    func resolveAny<T: Resolvable>(in machOImage: MachOImage) throws -> T
    func resolveOffset(in machOImage: MachOImage) -> Int
}

@MachOImageAllMembersGenerator
extension PointerProtocol {
    public func resolveAny<T: Resolvable>(in machOFile: MachOFile) throws -> T {
        return try T.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }

    public func resolve(in machOFile: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }
}

extension PointerProtocol {
    public func resolveOffset(in machOFile: MachOFile) -> Int {
        numericCast(machOFile.fileOffset(of: address))
    }

    public func resolveOffset(in machOImage: MachOImage) -> Int {
        Int(address) - machOImage.ptr.int
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    func resolve(in machOFile: MachOFile) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    func resolve(in machOImage: MachOImage) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: resolveOffset(in: machOImage), in: machOImage)
    }
}
