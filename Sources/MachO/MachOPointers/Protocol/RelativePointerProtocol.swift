import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativePointerProtocol<Pointee>: Sendable, Equatable {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger

    var relativeOffset: Offset { get }

    func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee

    func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T

    func resolveDirectOffset(from offset: Int) -> Int
    func resolveDirectAddress<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address

}

extension RelativePointerProtocol {
    public func resolveDirectOffset(from offset: Int) -> Int {
        return Int(offset) + Int(relativeOffset)
    }

    public func resolveDirectAddress<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        return context.advanceAddress(address, by: .init(relativeOffset))
    }

    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension RelativePointerProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Pointee {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public func resolve(from ptr: UnsafeRawPointer) throws -> Pointee {
        try resolve(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(at: offset, in: machO.context).")
    public func resolveAny<T: Resolvable>(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> T {
        try resolveAny(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(at: pointer, in: .inProcess).")
    public func resolveAny<T: Resolvable>(from ptr: UnsafeRawPointer) throws -> T {
        try resolveAny(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveDirectAddress(at: pointer, in: .inProcess).")
    public func resolveDirectOffset(from ptr: UnsafeRawPointer) throws -> UnsafeRawPointer {
        try resolveDirectAddress(at: ptr, in: InProcessContext.shared)
    }
}
