import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativeIndirectPointerProtocol<Pointee>: RelativePointerProtocol {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Resolved == Pointee
}

extension RelativeIndirectPointerProtocol {
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirect(at: address, in: context)
    }

    func resolveIndirect<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirectType(at: address, in: context).resolve(in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectAny(at: address, in: context)
    }

    func resolveIndirectAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectType(at: address, in: context).resolveAny(in: context)
    }

    public func resolveIndirectType<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> IndirectType {
        return try .resolve(at: resolveDirectAddress(at: address, in: context), in: context)
    }

    public func resolveIndirectOffset<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        return try resolveIndirectType(at: address, in: context).resolveAddress(in: context)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        try resolveUnlessNull(at: address, in: context)
    }

    /// A null pointer resolves to `nil`; any other pointer goes on to the
    /// protocol requirement, which is what `resolve(at:in:)` names from
    /// inside this extension and which skips the check.
    private func resolveUnlessNull<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(at: address, in: context)
    }
}
