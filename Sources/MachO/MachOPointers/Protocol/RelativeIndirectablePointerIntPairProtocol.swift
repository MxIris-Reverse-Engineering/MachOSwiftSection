import MachOKit
import MachOReading
import MachOKitExtensions

public protocol RelativeIndirectablePointerIntPairProtocol<Pointee>: RelativeIndirectablePointerProtocol {
    typealias Integer = Value.RawValue
    associatedtype Value: RawRepresentable where Value.RawValue: FixedWidthInteger
    var relativeOffsetPlusIndirectAndInt: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativeIndirectablePointerIntPairProtocol {
    public var relativeOffsetPlusIndirect: Offset {
        relativeOffsetPlusIndirectAndInt & ~mask
    }

    public var relativeOffset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast((relativeOffsetPlusIndirectAndInt & mask) >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}

extension RelativeIndirectablePointerIntPairProtocol where Pointee: OptionalProtocol {
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
