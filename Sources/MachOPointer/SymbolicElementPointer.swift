import MachOKit
import MachOReading

public enum SymbolicElementPointer<Context: Resolvable>: RelativeIndirectType {
    public typealias Resolved = SymbolicElement<Context>

    case symbol(UnsolvedSymbol)
    case address(UInt64)

    public func resolveOffset(in machOFile: MachOFile) -> Int {
        switch self {
        case .symbol(let unsolvedSymbol):
            return unsolvedSymbol.offset
        case .address(let address):
            return numericCast(machOFile.fileOffset(of: address))
        }
    }

    public func resolve(in machOFile: MachOFile) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Context.resolve(from: resolveOffset(in: machOFile), in: machOFile))
        }
    }

    public func resolveOffset(in machOImage: MachOImage) -> Int {
        switch self {
        case .symbol(let unsolvedSymbol):
            unsolvedSymbol.offset
        case .address(let address):
            Int(address) - machOImage.ptr.int
        }
    }

    public func resolve(in machOImage: MachOImage) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Context.resolve(from: resolveOffset(in: machOImage), in: machOImage))
        }
    }

    public func resolveAny<T: Resolvable>(in machOFile: MachOFile) throws -> T {
        fatalError()
    }

    public func resolveAny<T: Resolvable>(in machOImage: MachOImage) throws -> T {
        fatalError()
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            let resolvedFileOffset = fileOffset
            if let rebase = machOFile.resolveRebase(fileOffset: resolvedFileOffset) {
                return .address(rebase)
            } else {
                return try .address(machOFile.readElement(offset: resolvedFileOffset))
            }
        }
    }

    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Self {
        return try .address(machOImage.readElement(offset: imageOffset))
    }
}
