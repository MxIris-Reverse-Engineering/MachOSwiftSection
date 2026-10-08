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

// MARK: - Deprecated Mach-O and pointer forms

extension RelativeIndirectPointerProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: resolveIndirectType(at: offset, in: machO.context).")
    public func resolveIndirectType(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> IndirectType {
        try resolveIndirectType(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveIndirectOffset(at: offset, in: machO.context).")
    public func resolveIndirectOffset(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Int {
        try resolveIndirectOffset(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveIndirectType(at: pointer, in: .inProcess).")
    public func resolveIndirectType(from ptr: UnsafeRawPointer) throws -> IndirectType {
        try resolveIndirectType(at: ptr, in: InProcessContext.shared)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: OptionalProtocol {
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

    /// A null pointer resolves to `nil`. The deprecated forms call this
    /// rather than `resolve(at:in:)`, which from here binds to the protocol
    /// requirement and skips the check.
    private func resolveUnlessNull<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(at: address, in: context)
    }
}
