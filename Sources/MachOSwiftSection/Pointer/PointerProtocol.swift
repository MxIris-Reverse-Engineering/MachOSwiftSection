import Foundation
import MachOKit

public protocol PointerProtocol {
    associatedtype Pointee: Resolvable
    var address: UInt64 { get }

    func resolve(in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
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
