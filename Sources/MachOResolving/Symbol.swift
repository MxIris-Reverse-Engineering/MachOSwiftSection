import MachOKit
import MachOKitExtensions

/// A symbol as the resolution layer knows it: the offset it sits at, its
/// name, and whether the symbol-table entry was an undefined external
/// import.
///
/// This is a plain value — a bind-table entry read back through
/// `SymbolOrElementPointer`, or a row a symbol index vends — and it carries
/// no lookup behavior of its own. Looking a symbol *up* by offset is the
/// job of `MachOSymbols` (`symbols(offset:)`), deliberately one layer above
/// the ABI model (evolution proposal `self-contained-abi-layer`).
public struct Symbol: Hashable, Sendable {
    public let offset: Int

    public let name: String

    /// Whether the symbol-table entry was flagged as an undefined external
    /// import (`N_EXT` with `N_UNDF` type). Extracted from the `nlist` entry
    /// at collection time; the entry itself is not retained.
    public let isExternal: Bool

    public init(offset: Int, name: String, isExternal: Bool = false) {
        self.offset = offset
        self.name = name
        self.isExternal = isExternal
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
}
