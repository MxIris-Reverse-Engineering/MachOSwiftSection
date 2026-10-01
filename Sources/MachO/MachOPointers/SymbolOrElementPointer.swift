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

// MARK: - Deprecated Mach-O and pointer forms

extension SymbolOrElementPointer {
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    public func resolve() throws -> Resolved {
        try resolve(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Resolved {
        try resolve(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAddress(in: machO.context).")
    public func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int {
        // `MachOContext` converts addresses without failing; the requirement
        // is declared `throws` only for the contexts that can.
        try! resolveAddress(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: .inProcess).")
    public func resolveAny<T>() throws -> T where T: Resolvable {
        try resolveAny(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: machO.context).")
    public func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T {
        try resolveAny(in: machO.context)
    }
}

extension SymbolOrElementPointer where Element: OptionalProtocol {
    public func resolve(in context: some ReadingContext) throws -> Resolved {
        try resolveUnlessNull(in: context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    public func resolve() throws -> Resolved {
        try resolveUnlessNull(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    public func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Resolved {
        try resolveUnlessNull(in: machO.context)
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
