import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

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

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        if let machOFile = machO as? MachOFile, let symbol = machOFile.resolveBind(fileOffset: offset) {
            return .symbol(.init(offset: offset, name: symbol))
        } else {
            return try .element(.resolve(from: offset, in: machO))
        }
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self? {
        if let machOFile = machO as? MachOFile, let symbol = machOFile.resolveBind(fileOffset: offset) {
            return .symbol(.init(offset: offset, name: symbol))
        } else {
            return try Element.resolve(from: offset, in: machO).map { .element($0) }
        }
    }
    
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        return try .element(.resolve(from: ptr))
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
