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

extension Optional: Resolvable where Wrapped: Resolvable {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(at: address, in: context)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
}

extension String: Resolvable {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> String {
        try context.readString(at: address)
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        try context.readWrapperElement(at: address)
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
