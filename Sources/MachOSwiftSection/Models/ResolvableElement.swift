import MachOKit
import MachOFoundation

public enum ResolvableElement<Element: Resolvable>: Resolvable {
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
    
    public var resolved: Element? {
        switch self {
        case .symbol:
            return nil
        case .element(let element):
            return element
        }
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> ResolvableElement<Element> {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try .element(.resolve(from: fileOffset, in: machOFile))
        }
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> ResolvableElement<Element>? {
        if let symbol = machOFile.resolveBind(fileOffset: fileOffset) {
            return .symbol(.init(offset: fileOffset, stringValue: symbol))
        } else {
            return try Element.resolve(from: fileOffset, in: machOFile).map { .element($0) }
        }
    }
    
    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> ResolvableElement<Element> {
        return try .element(.resolve(from: imageOffset, in: machOImage))
    }
    
    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> ResolvableElement<Element>? {
        return try Element.resolve(from: imageOffset, in: machOImage).map { .element($0) }
    }
    
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> ResolvableElement<T> {
        switch self {
        case .symbol(let unsolvedSymbol):
            return .symbol(unsolvedSymbol)
        case .element(let context):
            return try .element(transform(context))
        }
    }
}

extension ResolvableElement where Element: OptionalProtocol, Element.Wrapped: Resolvable {
    public var asOptional: ResolvableElement<Element.Wrapped>? {
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
