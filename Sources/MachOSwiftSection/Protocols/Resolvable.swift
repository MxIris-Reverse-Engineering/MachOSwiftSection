import MachOKit

public protocol Resolvable {
    static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self
    static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self?
}

extension Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        return try machOFile.readElement(offset: fileOffset)
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        let result: Self = try resolve(from: fileOffset, in: machOFile)
        return .some(result)
    }
}

extension Optional: Resolvable where Wrapped: Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(from: fileOffset, in: machOFile)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
}

extension String: Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        return try machOFile.readString(offset: fileOffset) ?? ""
    }
}
