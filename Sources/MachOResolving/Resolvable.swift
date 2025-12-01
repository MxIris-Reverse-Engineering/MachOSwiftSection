import MachOKit
import MachOReading
import MachOExtensions

public protocol Resolvable: Sendable {
    static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self
    static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self?
    static func resolve(from ptr: UnsafeRawPointer) throws -> Self
    static func resolve(from ptr: UnsafeRawPointer) throws -> Self?
}

extension Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readElement(offset: offset)
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        let result: Self = try resolve(from: offset, in: machO)
        return .some(result)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try ptr.stripPointerTags().assumingMemoryBound(to: Self.self).pointee
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        let result: Self = try resolve(from: ptr)
        return .some(result)
    }
}

extension Optional: Resolvable where Wrapped: Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
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
}

extension String: Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readString(offset: offset)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try .init(cString: ptr.stripPointerTags().assumingMemoryBound(to: CChar.self))
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        try machO.readWrapperElement(offset: offset)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try .init(layout: ptr.stripPointerTags().assumingMemoryBound(to: Layout.self).pointee, offset: ptr.int)
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
