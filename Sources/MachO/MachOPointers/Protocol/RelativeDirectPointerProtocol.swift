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

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        try resolveUnlessNull(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        try resolveUnlessNull(at: ptr, in: InProcessContext.shared)
    }

    /// A null pointer resolves to `nil` instead of the bytes at its own
    /// location. The deprecated forms call this rather than
    /// `resolve(at:in:)`: from here that name binds to the protocol
    /// requirement, whose witness is the unconstrained implementation
    /// without this check.
    private func resolveUnlessNull<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(at: address, in: context)
    }
}
