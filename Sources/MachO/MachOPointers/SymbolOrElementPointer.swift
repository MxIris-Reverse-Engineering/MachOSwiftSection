import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public typealias RelativeSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectablePointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeIndirectSymbolOrElementPointer<Element: Resolvable> = RelativeIndirectPointer<SymbolOrElement<Element>, SymbolOrElementPointer<Element>>

public typealias RelativeSymbolOrElementPointerIntPair<Element: Resolvable, Value: RawRepresentable> = RelativeIndirectablePointerIntPair<SymbolOrElement<Element>, Value, SymbolOrElementPointer<Element>> where Value.RawValue: FixedWidthInteger

public enum SymbolOrElementPointer<Element: Resolvable>: RelativeIndirectType {
    public typealias Resolved = SymbolOrElement<Element>

    case symbol(Symbol)
    case address(UInt64)

    public func resolve(in context: some ReadingContext) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address:
            return try .element(Element.resolve(at: resolveAddress(in: context), in: context))
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

    public func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T {
        fatalError("resolveAny is not supported for SymbolOrElementPointer with ReadingContext")
    }

    /// Reads the pointer stored at `address`: the symbol dyld binds there when
    /// the element lives in another image, otherwise the rebased target or
    /// the stored address.
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        if let resolver = context.bindRebaseResolver {
            let offset = try context.offsetFromAddress(address)
            if let symbol = resolver.resolveBind(fileOffset: offset) {
                return .symbol(.init(offset: offset, name: symbol))
            }
            if let rebase = resolver.resolveRebase(fileOffset: offset) {
                return .address(rebase)
            }
        }
        return try .address(context.readElement(at: address))
    }
}

extension SymbolOrElementPointer where Element: OptionalProtocol {
    public func resolve(in context: some ReadingContext) throws -> Resolved {
        try resolveUnlessNull(in: context)
    }

    /// A stored address that is null once its tag bits are stripped
    /// resolves to a `nil` element.
    private func resolveUnlessNull(in context: some ReadingContext) throws -> Resolved {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .address(let address) where stripPointerTags(of: address) == 0:
            return .element(.none)
        case .address:
            return try .element(Element.resolve(at: resolveAddress(in: context), in: context))
        }
    }
}
