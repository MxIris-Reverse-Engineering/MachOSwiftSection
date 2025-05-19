import MachOKit
import Foundation

//public protocol ResolvableElementPointerProtocol: PointerProtocol, RelativeIndirectType where Resolved == ResolvableElement<ResolvedElement>, Resolved == Pointee {
//    associatedtype ResolvedElement: Resolvable
//    static func symbol(_ symbol: UnsolvedSymbol) -> Self
//    static func address(_ address: UInt64) -> Self
//}
//
//extension ResolvableElementPointerProtocol {
//    
//}

public enum SignedResolvableElementPointer<Context: Resolvable>: RelativeIndirectType {
    public typealias Resolved = ResolvableElement<Context>

    case symbol(UnsolvedSymbol)
    case address(UInt64)

    public func resolveOffset(in machOFile: MachOFile) -> Int {
        switch self {
        case .symbol(let unsolvedSymbol):
            return unsolvedSymbol.offset
        case .address(let address):
            if let cache = machOFile.cache, cache.cpu.type == .arm64 {
                return numericCast(address & 0x7FFFFFFF)
            } else {
                return numericCast(machOFile.fileOffset(of: address))
            }
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

    public func resolveAny<T>(in machOFile: MachOFile) throws -> T {
        fatalError()
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try .address(machOFile.readElement(offset: fileOffset))
        }
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        let resolved: Self = try resolve(from: fileOffset, in: machOFile)
        return resolved
    }
}
