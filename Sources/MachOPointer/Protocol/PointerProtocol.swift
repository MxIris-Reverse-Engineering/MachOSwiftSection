import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public protocol PointerProtocol: Resolvable, Sendable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Pointee
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> T
    func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int
}

extension PointerProtocol {
    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> T {
        return try T.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }

    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machOFile), in: machOFile)
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
