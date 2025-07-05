import MachOKit
import MachOReading
import MachOExtensions

public protocol Resolvable {
    static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self
    static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self?
}

extension Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readElement(offset: offset)
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        let result: Self = try resolve(from: offset, in: machO)
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
}

extension String: Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        return try machO.readString(offset: offset)
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        try machO.readWrapperElement(offset: offset)
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
