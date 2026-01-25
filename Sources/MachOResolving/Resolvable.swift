import MachOKit
import MachOReading
import MachOExtensions

public protocol Resolvable: Sendable {
    static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self
    static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self?
    static func resolve(from ptr: UnsafeRawPointer) throws -> Self
    static func resolve(from ptr: UnsafeRawPointer) throws -> Self?
    static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self
    static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self?
}

extension Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readElement(offset: offset)
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self? {
        let result: Self = try resolve(from: offset, in: machO)
        return .some(result)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try ptr.stripPointerTags().readElement()
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        let result: Self = try resolve(from: ptr)
        return .some(result)
    }
    
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
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(from: offset, in: machO)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(from: ptr)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
    
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
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readString(offset: offset)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        return try ptr.stripPointerTags().readString()
    }
    
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> String {
        try context.readString(at: address)
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        try machO.readWrapperElement(offset: offset)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try ptr.stripPointerTags().readWrapperElement()
    }
    
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
        return try .resolve(from: offset, in: machO)
    }
}
