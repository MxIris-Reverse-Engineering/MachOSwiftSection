import Foundation
import MachOKit

public protocol RelativePointerProtocol<Pointee> {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger
    
    var relativeOffset: Offset { get }
    
    func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee
    func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Pointee
    
    func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T
    func resolveAny<T>(from imageOffset: Int, in machOImage: MachOImage) throws -> T
    
    func resolveDirectOffset(from offset: Int) -> Int
}

extension RelativePointerProtocol {
    public func resolveDirectOffset(from offset: Int) -> Int {
        return Int(offset) + Int(relativeOffset)
    }
    
    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}
