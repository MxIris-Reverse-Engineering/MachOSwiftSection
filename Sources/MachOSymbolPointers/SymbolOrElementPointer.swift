import MachOKit
import MachOReading
import MachOPointers
import MachOSymbols
import MachOResolving
import MachOExtensions

public typealias RelativeSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectablePointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeIndirectSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectPointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeSymbolOrElementPointerIntPair<Element: Resolvable, Value: RawRepresentable> = RelativeIndirectablePointerIntPair<SymbolOrElement<Element>, Value, SymbolOrElementPointer<Element>> where Value.RawValue: FixedWidthInteger

public enum SymbolOrElementPointer<Element: Resolvable>: RelativeIndirectType {
    public typealias Resolved = SymbolOrElement<Element>

    case symbol(Symbol)
    case address(UInt64)

    public func resolve() throws -> Resolved {
        switch self {
        case .symbol:
            fatalError()
        case .address(let address):
            return try .element(Element.resolve(from: .init(bitPattern: stripPointerTags(of: address).uint)))
        }
    }

    public func resolve<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Element.resolve(from: resolveOffset(in: machO), in: machO))
        }
    }

    public func resolve<Context: ReadingContext>(in context: Context) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Element.resolve(at: resolveAddress(in: context), in: context))
        }
    }

    public func resolveOffset<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) -> Int {
        switch self {
        case .symbol(let unsolvedSymbol):
            return unsolvedSymbol.offset
        case .address(let address):
            return numericCast(machO.resolveOffset(at: machO.stripPointerTags(of: address)))
        }
    }

    public func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address {
        switch self {
        case .symbol(let symbol):
            return try context.addressFromOffset(symbol.offset)
        case .address(let address):
            return try context.addressFromVirtualAddress(address)
        }
    }

    public func resolveAny<T>() throws -> T where T: Resolvable {
        fatalError()
    }

    public func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> T {
        fatalError()
    }

    public func resolveAny<T: Resolvable, Context: ReadingContext>(in context: Context) throws -> T {
        fatalError("resolveAny is not supported for SymbolOrElementPointer with ReadingContext")
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
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

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        if let machOFileContext = context as? MachOContext<MachOFile> {
            let machOFile = machOFileContext.machO
            let offset = try context.offsetFromAddress(address)
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
            return try .address(context.readElement(at: address))
        }
    }
}
