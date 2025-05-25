import Foundation
import MachOKit

public protocol PointerProtocol: Resolvable {
    associatedtype Pointee: Resolvable
    
    var address: UInt64 { get }

    func resolve(in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
    
    func resolve(in machOImage: MachOImage) throws -> Pointee
    func resolveAny<T>(in machOImage: MachOImage) throws -> T
    func resolveOffset(in machOImage: MachOImage) -> Int
}

extension PointerProtocol {
    public func resolveOffset(in machOFile: MachOFile) -> Int {
        if let cache = machOFile.cache, cache.cpu.type == .arm64 {
            numericCast(address & 0x7FFFFFFF)
        } else {
            numericCast(machOFile.fileOffset(of: address))
        }
    }

    public func resolveAny<T>(in machOFile: MachOFile) throws -> T {
        return try machOFile.readElement(offset: resolveOffset(in: machOFile))
    }

    public func resolve(in machOFile: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }
}

extension PointerProtocol {
    public func resolveOffset(in machOImage: MachOImage) -> Int {
        Int(address) - machOImage.ptr.int
    }

    public func resolveAny<T>(in machOImage: MachOImage) throws -> T {
        return try machOImage.assumingElement(offset: resolveOffset(in: machOImage))
    }

    public func resolve(in machOImage: MachOImage) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machOImage), in: machOImage)
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
