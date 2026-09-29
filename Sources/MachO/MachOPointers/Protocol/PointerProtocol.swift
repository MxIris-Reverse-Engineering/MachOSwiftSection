import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol PointerProtocol<Pointee>: Resolvable, Sendable, Equatable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve() throws -> Pointee
    func resolveAny<T: Resolvable>() throws -> T

    func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee
    func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T
    func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int

    func resolve(in context: some ReadingContext) throws -> Pointee
    func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address
}

extension PointerProtocol {
    public func resolve() throws -> Pointee {
        return try Pointee.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolveAny<T: Resolvable>() throws -> T {
        return try T.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T {
        return try T.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int {
        machO.resolveOffset(at: address)
    }

    public func resolve(in context: some ReadingContext) throws -> Pointee {
        return try Pointee.resolve(at: resolveAddress(in: context), in: context)
    }

    public func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T {
        return try T.resolve(at: resolveAddress(in: context), in: context)
    }

    public func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address {
        return try context.addressFromVirtualAddress(address)
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }

    public func resolve() throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(from: .init(bitPattern: UInt(stripPointerTags(of: address))))
    }

    public func resolve(in context: some ReadingContext) throws -> Pointee {
        guard address != 0 else { return nil }
        return try Pointee.resolve(at: resolveAddress(in: context), in: context)
    }
}
