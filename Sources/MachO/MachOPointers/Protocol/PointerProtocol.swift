import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol PointerProtocol<Pointee>: Resolvable, Sendable, Equatable {
    associatedtype Pointee: Resolvable

    var address: UInt64 { get }

    func resolve(in context: some ReadingContext) throws -> Pointee
    func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address
}

extension PointerProtocol {
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
    public func resolve(in context: some ReadingContext) throws -> Pointee {
        try resolveUnlessNull(in: context)
    }

    /// A null pointer resolves to `nil`; any other address goes on to the
    /// protocol requirement, which is what `resolve(in:)` names from inside
    /// this extension and which skips the check.
    private func resolveUnlessNull(in context: some ReadingContext) throws -> Pointee {
        guard address != 0 else { return nil }
        return try resolve(in: context)
    }
}
