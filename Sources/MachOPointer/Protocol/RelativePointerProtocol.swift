import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativePointerProtocol<Pointee>: Sendable, Equatable {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger
    
    var relativeOffset: Offset { get }
    
    func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Pointee
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> T
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
