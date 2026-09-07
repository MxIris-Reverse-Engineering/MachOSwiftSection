import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions
@_spi(Internals) import Demangling
import FoundationToolbox

extension Symbol {
    /// Whether ``resolve(from:in:)`` answers from `SymbolIndexStore` (every
    /// name at the offset, index built on first use) or from MachOKit's own
    /// symbol table (one name, no index). Process-wide.
    @Mutex
    public static var resolvesSymbolUsingIndexStore: Bool = true

    /// Looks the symbol at `offset` up — `SymbolIndexStore` or MachOKit's
    /// symbol table depending on ``resolvesSymbolUsingIndexStore`` — and
    /// throws when there is none.
    ///
    /// A lookup, not a read: this is why it lives here and not on the value
    /// type in `MachOResolving` (evolution proposal `self-contained-abi-layer`).
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: offset, in: machO))
    }

    /// Optional form of ``resolve(from:in:)-swift.type.method``.
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self? {
        if resolvesSymbolUsingIndexStore {
            return machO.symbols(offset: offset)?.first
        } else {
            return machO.symbol(for: offset, inSection: 0, isGlobalOnly: false)?.asCurrentSymbol
        }
    }
}

extension Symbol: MachOSymbols.SymbolProtocol {}

public protocol SymbolProtocol {
    var name: String { get }
}

extension MachOSymbols.SymbolProtocol {
    public var demangledNode: Node {
        get throws {
            try demangleAsNodeTransient(name)
        }
    }
}

extension MachOKit.SymbolProtocol {
    fileprivate var asCurrentSymbol: MachOResolving.Symbol {
        .init(offset: offset, name: name, isExternal: nlist.isExternal)
    }
}

extension MachOKit.ExportedSymbol: MachOSymbols.SymbolProtocol {}
extension MachOKit.MachOFile.Symbol: MachOSymbols.SymbolProtocol {}
extension MachOKit.MachOImage.Symbol: MachOSymbols.SymbolProtocol {}
