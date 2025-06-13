@resultBuilder
public enum SemanticStringBuilder {
    public typealias Element = any SemanticStringComponent

    public static func buildBlock() -> [Element] { [] }

    public static func buildPartialBlock(first: Void) -> [Element] { [] }
    
    public static func buildPartialBlock(first: Never) -> [Element] {}
    
    public static func buildPartialBlock(first: Element) -> [Element] { [first] }
    
    public static func buildPartialBlock(first: [Element]) -> [Element] { first }
    
    public static func buildPartialBlock(first: SemanticString) -> [Element] { first.components }
    
    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] { accumulated + [next] }
    
    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] { accumulated + next }
    
    public static func buildPartialBlock(accumulated: [Element], next: SemanticString) -> [Element] { accumulated + next.components }

    public static func buildOptional(_ components: [Element]?) -> [Element] { components ?? [] }

    public static func buildEither(first: [Element]) -> [Element] { first }

    public static func buildEither(second: [Element]) -> [Element] { second }

    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }

    public static func buildFinalResult(_ components: [Element]) -> SemanticString { .init(components: components) }
}
