import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativePointerProtocol<Pointee>: Sendable, Equatable {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger

    var relativeOffset: Offset { get }
    func resolve(from ptr: UnsafeRawPointer) throws -> Pointee
    func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Pointee
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> T
    func resolveAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T
    func resolveDirectOffset(from offset: Int) -> Int
    func resolveDirectOffset(from ptr: UnsafeRawPointer) throws -> UnsafeRawPointer
}

extension RelativePointerProtocol {
    public func resolveDirectOffset(from ptr: UnsafeRawPointer) throws -> UnsafeRawPointer {
        try ptr.stripPointerTags().advanced(by: .init(relativeOffset))
    }

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
