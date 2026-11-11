import MachOKit
import MachOReading
import MachOKitExtensions
import MachOResolving

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointerProtocol {}

extension RelativeDirectPointerProtocol {
    public func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Pointee {
        return try resolveDirect(at: address, in: context)
    }

    func resolveDirect<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Pointee {
        return try Pointee.resolve(at: resolveDirectAddress(at: address, in: context), in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> T {
        return try resolveDirectAny(at: address, in: context)
    }

    func resolveDirectAny<T: Resolvable, Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> T {
        return try T.resolve(at: resolveDirectAddress(at: address, in: context), in: context)
    }
}

extension RelativeDirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        try resolveUnlessNull(at: address, in: context)
    }

    /// A null pointer resolves to `nil` instead of the bytes at its own
    /// location; any other pointer goes on to the protocol requirement, which
    /// is what `resolve(at:in:)` names from inside this extension and whose
    /// witness is the unconstrained implementation without this check.
    private func resolveUnlessNull<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(at: address, in: context)
    }
}
