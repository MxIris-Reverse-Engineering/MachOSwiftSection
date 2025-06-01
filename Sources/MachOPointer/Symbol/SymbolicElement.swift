import MachOKit
import MachOReading
import MachOExtensions

public enum SymbolicElement<Element: Resolvable>: Resolvable {
    case symbol(UnsolvedSymbol)
    case element(Element)

    public var isResolved: Bool {
        switch self {
        case .symbol:
            return false
        case .element:
            return true
        }
    }
    
    public var symbol: UnsolvedSymbol? {
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

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> SymbolicElement<Element> {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try .element(.resolve(from: fileOffset, in: machOFile))
        }
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> SymbolicElement<Element>? {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try Element.resolve(from: fileOffset, in: machOFile).map { .element($0) }
        }
    }
    
    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> SymbolicElement<Element> {
        return try .element(.resolve(from: imageOffset, in: machOImage))
    }
    
    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> SymbolicElement<Element>? {
        return try Element.resolve(from: imageOffset, in: machOImage).map { .element($0) }
    }
    
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> SymbolicElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try .element(transform(context))
        }
    }
    
    public func mapOptional<T>(_ transform: (Element) throws -> T?) rethrows -> SymbolicElement<T>? {
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
    
    public func flatMap<T>(_ transform: (Element) throws -> SymbolicElement<T>) rethrows -> SymbolicElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try transform(context)
        }
    }
}

extension SymbolicElement where Element: OptionalProtocol, Element.Wrapped: Resolvable {
    public var asOptional: SymbolicElement<Element.Wrapped>? {
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
