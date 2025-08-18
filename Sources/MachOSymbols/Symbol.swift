import MachOKit
import MachOMacro
import MachOReading
import MachOResolving
import MachOExtensions
import Demangle

public struct Symbol: Resolvable, Hashable, SymbolProtocol {
    public let offset: Int

    public let stringValue: String

    public var name: String { stringValue }
    
    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
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
