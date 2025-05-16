import Foundation
import MachOKit

public protocol RelativePointerProtocol<Pointee> {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger
    var relativeOffset: Offset { get }
    func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T
    func resolveDirectFileOffset(from fileOffset: Int) -> Int
}

extension RelativePointerProtocol {
    public func resolveDirectFileOffset(from fileOffset: Int) -> Int {
        return Int(fileOffset) + Int(relativeOffset)
    }

    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}
