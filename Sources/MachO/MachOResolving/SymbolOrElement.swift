import MachOKit
import MachOReading
import MachOKitExtensions

public enum SymbolOrElement<Element: Resolvable>: Resolvable {
    case symbol(Symbol)
    case element(Element)

    public var isResolved: Bool {
        switch self {
        case .symbol:
            return false
        case .element:
            return true
        }
    }

    public var symbol: Symbol? {
        switch self {
        case .symbol(let unsolvedSymbol):
            return unsolvedSymbol
        case .element:
            return nil
        }
    }

    public var resolved: Element? {
        switch self {
        case .symbol:
            return nil
        case .element(let element):
            return element
        }
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        if let symbol = boundSymbol(at: address, in: context) {
            return .symbol(symbol)
        } else {
            return .element(try Element.resolve(at: address, in: context))
        }
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self? {
        if let symbol = boundSymbol(at: address, in: context) {
            return .symbol(symbol)
        } else {
            return try Element.resolve(at: address, in: context).map { .element($0) }
        }
    }

    /// The symbol dyld binds at `address`, when the context reads a file whose
    /// bind table names one there: the element lives in another image, so
    /// there is nothing at `address` to read.
    private static func boundSymbol<Context: ReadingContext>(at address: Context.Address, in context: Context) -> Symbol? {
        guard let resolver = context.bindRebaseResolver, let offset = try? context.offsetFromAddress(address), let name = resolver.resolveBind(fileOffset: offset) else {
            return nil
        }
        return Symbol(offset: offset, name: name)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
    
    public func map<T, E: Swift.Error>(_ transform: (Element) throws(E) -> T) throws(E) -> SymbolOrElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try .element(transform(context))
        }
    }

    public func mapOptional<T, E: Swift.Error>(_ transform: (Element) throws(E) -> T?) throws(E) -> SymbolOrElement<T>? {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            if let transformed = try transform(context) {
                return .element(transformed)
            } else {
                return nil
            }
        }
    }

    public func flatMap<T, E: Swift.Error>(_ transform: (Element) throws(E) -> SymbolOrElement<T>) throws(E) -> SymbolOrElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try transform(context)
        }
    }
}

extension SymbolOrElement where Element: OptionalProtocol, Element.Wrapped: Resolvable {
    public var asOptional: SymbolOrElement<Element.Wrapped>? {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let optionalContext):
            if let context = optionalContext.flatMap({ $0 }) {
                return .element(context)
            } else {
                return nil
            }
        }
    }
}

extension SymbolOrElement: Equatable where Element: Equatable {}

extension SymbolOrElement: Hashable where Element: Hashable {}
