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

    // The deprecated forms stay requirements, unlike everywhere else: `Pointer`
    // conforms to this protocol and to `RelativeIndirectType`, which declares
    // the same members, and two unrelated protocol extensions each providing
    // them would make every call on a `Pointer` ambiguous. A requirement and
    // its default deprecated together warn only at call sites.
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    func resolve() throws -> Pointee
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: .inProcess).")
    func resolveAny<T: Resolvable>() throws -> T
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: machO.context).")
    func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAddress(in: machO.context).")
    func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int
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

// MARK: - Deprecated Mach-O and pointer forms

extension PointerProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    public func resolve() throws -> Pointee {
        try resolve(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: .inProcess).")
    public func resolveAny<T: Resolvable>() throws -> T {
        try resolveAny(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        try resolve(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: machO.context).")
    public func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T {
        try resolveAny(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAddress(in: machO.context).")
    public func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int {
        // `MachOContext` converts addresses without failing; the requirement
        // is declared `throws` only for the contexts that can.
        try! resolveAddress(in: machO.context)
    }
}

extension PointerProtocol where Pointee: OptionalProtocol {
    public func resolve(in context: some ReadingContext) throws -> Pointee {
        try resolveUnlessNull(in: context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    public func resolve() throws -> Pointee {
        try resolveUnlessNull(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        try resolveUnlessNull(in: machO.context)
    }

    /// A null pointer resolves to `nil`. The deprecated forms call this
    /// rather than `resolve(in:)`, which from here binds to the protocol
    /// requirement and skips the check.
    private func resolveUnlessNull(in context: some ReadingContext) throws -> Pointee {
        guard address != 0 else { return nil }
        return try resolve(in: context)
    }
}
