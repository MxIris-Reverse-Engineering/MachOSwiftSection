import MachOKit

import MachOReading
import MachOResolving
import MachOExtensions
import Demangle

public struct Symbol: Resolvable, SymbolProtocol, Hashable {
    public let offset: Int

    public let name: String
    
    public let nlist: (any NlistProtocol)?
    
    public init(offset: Int, name: String, nlist: (any NlistProtocol)? = nil) {
        self.offset = offset
        self.name = name
        self.nlist = nlist
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: offset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        if let symbol = machO.symbols(offset: offset)?.first {
            return symbol
        }
        return nil
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
        hasher.combine(name)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.offset == rhs.offset && lhs.name == rhs.name
    }
}

public protocol SymbolProtocol {
    var name: String { get }
}

extension MachOSymbols.SymbolProtocol {
    public var demangledNode: Node {
        get throws {
            try demangleAsNode(name)
        }
    }
}

extension MachOKit.SymbolProtocol {
    public var demangledNode: Node {
        get throws {
            try demangleAsNode(name)
        }
    }
}

extension MachOKit.ExportedSymbol: MachOSymbols.SymbolProtocol {}
