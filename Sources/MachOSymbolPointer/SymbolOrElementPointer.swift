import MachOKit
import MachOReading
import MachOPointer
import MachOSymbols
import MachOResolving
import MachOExtensions

public typealias RelativeSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectablePointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeIndirectSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectPointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeSymbolOrElementPointerIntPair<Element: Resolvable, Value: RawRepresentable> = RelativeIndirectablePointerIntPair<SymbolOrElement<Element>, Value, SymbolOrElementPointer<Element>> where Value.RawValue: FixedWidthInteger

public enum SymbolOrElementPointer<Context: Resolvable>: RelativeIndirectType {
    public typealias Resolved = SymbolOrElement<Context>

    case symbol(Symbol)
    case address(UInt64)

    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Resolved {
        switch self {
        case let .symbol(unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Context.resolve(from: resolveOffset(in: machO), in: machO))
        }
    }

    public func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int {
        switch self {
        case let .symbol(unsolvedSymbol):
            return unsolvedSymbol.offset
        case let .address(address):
            return numericCast(machO.resolveOffset(at: address))
        }
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> T {
        fatalError()
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        if let machOFile = machO as? MachOFile {
            if let symbol = machOFile.resolveBind(fileOffset: offset) {
                return .symbol(.init(offset: offset, name: symbol))
            } else {
                let resolvedFileOffset = offset
                if let rebase = machOFile.resolveRebase(fileOffset: resolvedFileOffset) {
                    return .address(rebase)
                } else {
                    return try .address(machOFile.readElement(offset: resolvedFileOffset))
                }
            }
        } else {
            return try .address(machO.readElement(offset: offset))
        }
    }
}
