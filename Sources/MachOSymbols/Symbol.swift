import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions
import Demangling
import FoundationToolbox

public struct Symbol: AsyncResolvable, SymbolProtocol, Hashable {
    public let offset: Int

    public let name: String

    public let nlist: (any NlistProtocol)?

    public init(offset: Int, name: String, nlist: (any NlistProtocol)? = nil) {
        self.offset = offset
        self.name = name
        self.nlist = nlist
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: offset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self? {
        if resolvesSymbolUsingIndexStore {
            return machO.symbols(offset: offset)?.first
        } else {
            return machO.symbol(for: offset, inSection: 0, isGlobalOnly: false)?.asCurrentSymbol
        }
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self {
        try await required(resolve(from: offset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) async throws -> Self? {
        if resolvesSymbolUsingIndexStore {
            return await machO.symbols(offset: offset)?.first
        } else {
            return machO.symbol(for: offset, inSection: 0, isGlobalOnly: false)?.asCurrentSymbol
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
        hasher.combine(name)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.offset == rhs.offset && lhs.name == rhs.name
    }
    
    public enum AddressFormat {
        case hex
        case decimal
    }
    
    public func addressString(format: AddressFormat, in machO: some MachORepresentableWithCache) -> String {
        switch format {
        case .hex:
            return "0x" + String(machO.address(forOffset: offset), radix: 16, uppercase: true)
        case .decimal:
            return String(machO.address(forOffset: offset), radix: 10)
        }
    }
    
    @Mutex
    public static var resolvesSymbolUsingIndexStore: Bool = true
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
    fileprivate var asCurrentSymbol: MachOSymbols.Symbol {
        .init(offset: offset, name: name, nlist: nlist)
    }
}

extension MachOKit.ExportedSymbol: MachOSymbols.SymbolProtocol {}
extension MachOKit.MachOFile.Symbol: MachOSymbols.SymbolProtocol {}
extension MachOKit.MachOImage.Symbol: MachOSymbols.SymbolProtocol {}
