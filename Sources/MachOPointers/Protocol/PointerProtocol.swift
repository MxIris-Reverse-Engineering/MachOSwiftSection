import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol PointerProtocol<Pointee>: Resolvable, Sendable, Equatable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve() throws -> Pointee
    func resolveAny<T: Resolvable>() throws -> T

    func resolve<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> Pointee
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> T
    func resolveOffset<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) -> Int

    func resolve<Context: ReadingContext>(in context: Context) throws -> Pointee
    func resolveAny<T: Resolvable, Context: ReadingContext>(in context: Context) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address
}

extension PointerProtocol {
    public func resolve() throws -> Pointee {
        return try Pointee.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolveAny<T: Resolvable>() throws -> T {
        return try T.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolve<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> T {
        return try T.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolveOffset<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) -> Int {
        machO.resolveOffset(at: address)
    }

    public func resolve<Context: ReadingContext>(in context: Context) throws -> Pointee {
        return try Pointee.resolve(at: resolveAddress(in: context), in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(in context: Context) throws -> T {
        return try T.resolve(at: resolveAddress(in: context), in: context)
    }

    public func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address {
        return try context.addressFromVirtualAddress(address)
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    public func resolve<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolve() throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolve<Context: ReadingContext>(in context: Context) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(at: resolveAddress(in: context), in: context)
    }
}
