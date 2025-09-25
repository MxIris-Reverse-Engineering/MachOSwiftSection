import MachOKit
import MachOMacro
import MachOReading
import MachOResolving
import MachOExtensions

public protocol PointerProtocol<Pointee>: Resolvable, Sendable, Equatable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Pointee
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> T
    func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int
}

extension PointerProtocol {
    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> T {
        return try T.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int {
        machO.resolveOffset(at: address)
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }
}
