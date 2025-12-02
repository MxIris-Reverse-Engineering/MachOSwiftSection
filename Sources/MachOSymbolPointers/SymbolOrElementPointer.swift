import MachOKit
import MachOReading
import MachOPointers
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

    public func resolve() throws -> Resolved {
        switch self {
        case .symbol:
            fatalError()
        case .address(let address):
            return try .element(Context.resolve(from: .init(bitPattern: stripPointerTags(of: address).uint)))
        }
    }

    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Context.resolve(from: resolveOffset(in: machO), in: machO))
        }
    }

    public func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int {
        switch self {
        case .symbol(let unsolvedSymbol):
            return unsolvedSymbol.offset
        case .address(let address):
            return numericCast(machO.resolveOffset(at: machO.stripPointerTags(of: address)))
        }
    }

    public func resolveAny<T>() throws -> T where T: Resolvable {
        fatalError()
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

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        return try .address(ptr.stripPointerTags().assumingMemoryBound(to: UInt64.self).pointee)
    }
}
