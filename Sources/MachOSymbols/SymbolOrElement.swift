import MachOKit
import MachOReading
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

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machO: MachO) throws -> SymbolOrElement<Element> {
        if let machOFile = machO as? MachOFile, let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try .element(.resolve(from: fileOffset, in: machO))
        }
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machO: MachO) throws -> SymbolOrElement<Element>? {
        if let machOFile = machO as? MachOFile, let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try Element.resolve(from: fileOffset, in: machO).map { .element($0) }
        }
    }
    
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> SymbolOrElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try .element(transform(context))
        }
    }
    
    public func mapOptional<T>(_ transform: (Element) throws -> T?) rethrows -> SymbolOrElement<T>? {
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
    
    public func flatMap<T>(_ transform: (Element) throws -> SymbolOrElement<T>) rethrows -> SymbolOrElement<T> {
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
