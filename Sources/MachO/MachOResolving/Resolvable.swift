import MachOKit
import MachOReading
import MachOKitExtensions

public protocol Resolvable: Sendable {
    static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self
    static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self?
}

extension Resolvable {
    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self {
        try context.readElement(at: address)
    }

    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self? {
        let result: Self = try resolve(at: address, in: context)
        return .some(result)
    }
}

// MARK: - Deprecated Mach-O and pointer forms
//
// Each deprecated form sits where its implementation used to — the protocol
// extension, a constrained extension, a concrete conformer — so overload
// resolution picks the same form it always did, notably the `Self` form over
// the `Self?` form for a wrapper or a `String`.

extension Resolvable {
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

extension Optional: Resolvable where Wrapped: Resolvable {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(at: address, in: context)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

extension String: Resolvable {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> String {
        try context.readString(at: address)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        try context.readWrapperElement(at: address)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

extension Int: Resolvable {}
extension UInt: Resolvable {}

extension Int8: Resolvable {}
extension UInt8: Resolvable {}

extension Int16: Resolvable {}
extension UInt16: Resolvable {}

extension Int32: Resolvable {}
extension UInt32: Resolvable {}

extension Int64: Resolvable {}
extension UInt64: Resolvable {}

extension Float: Resolvable {}
extension Double: Resolvable {}


extension LocatableLayoutWrapper where Self: Resolvable {
    package func asMachOWrapper(in machO: MachOImage) throws -> Self {
        let offset = Int(bitPattern: UInt(bitPattern: offset) - machO.ptr.bitPattern.uint)
        return try .resolve(at: offset, in: machO.context)
    }
}
