import MachOKit
import MachOReading
import MachOKitExtensions

/// An asynchronous spelling of the Mach-O form of ``Resolvable``. Nothing in
/// the package calls it, and reading never suspends; resolve synchronously
/// through a `ReadingContext` instead.
@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
public protocol AsyncResolvable: Resolvable {
    static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) async throws -> Self
    static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) async throws -> Self?
}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension AsyncResolvable {
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) async throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) async throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }
}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Optional: AsyncResolvable where Wrapped: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension String: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Int: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension UInt: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Int8: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension UInt8: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Int16: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension UInt16: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Int32: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension UInt32: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Int64: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension UInt64: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Float: AsyncResolvable {}

@available(*, deprecated, message: "Resolve synchronously through a ReadingContext: resolve(at: offset, in: machO.context).")
extension Double: AsyncResolvable {}
