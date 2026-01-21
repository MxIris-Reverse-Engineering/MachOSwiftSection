import MachOKit
import MachOReading
import MachOExtensions

public protocol AsyncResolvable: Resolvable {
    static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self
    static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self?
}

extension AsyncResolvable {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self {
        return try machO.readElement(offset: offset)
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self? {
        let result: Self = try await resolve(from: offset, in: machO)
        return .some(result)
    }
}

extension Optional: AsyncResolvable where Wrapped: AsyncResolvable {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self {
        let result: Wrapped? = try await Wrapped.resolve(from: offset, in: machO)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
}

extension String: AsyncResolvable {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self {
        return try machO.readString(offset: offset)
    }
}

extension AsyncResolvable where Self: LocatableLayoutWrapper {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self {
        try machO.readWrapperElement(offset: offset)
    }
}

extension Int: AsyncResolvable {}
extension UInt: AsyncResolvable {}

extension Int8: AsyncResolvable {}
extension UInt8: AsyncResolvable {}

extension Int16: AsyncResolvable {}
extension UInt16: AsyncResolvable {}

extension Int32: AsyncResolvable {}
extension UInt32: AsyncResolvable {}

extension Int64: AsyncResolvable {}
extension UInt64: AsyncResolvable {}

extension Float: AsyncResolvable {}
extension Double: AsyncResolvable {}
