import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativeIndirectablePointerProtocol<Pointee>: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var relativeOffsetPlusIndirect: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativeIndirectablePointerProtocol {
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }
}

extension RelativeIndirectablePointerProtocol {
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        return try resolveIndirectable(at: address, in: context)
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        return try resolveIndirectableAny(at: address, in: context)
    }

    func resolveIndirectable<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(at: address, in: context)
        } else {
            return try resolveDirect(at: address, in: context)
        }
    }

    public func resolveIndirectableType<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectType(at: address, in: context)
    }

    func resolveIndirectableAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T {
        if isIndirect {
            return try resolveIndirectAny(at: address, in: context)
        } else {
            return try resolveDirectAny(at: address, in: context)
        }
    }

    public func resolveIndirectableOffset<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        guard let indirectType = try resolveIndirectableType(at: address, in: context) else {
            return try resolveDirectAddress(at: address, in: context)
        }
        return try indirectType.resolveAddress(in: context)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: OptionalProtocol {
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
