@resultBuilder
public enum SemanticStringBuilder {
    public typealias Element = any SemanticStringComponent
    /// Empty block
    public static func buildBlock() -> [Element] { [] }

    public static func buildPartialBlock(first: Element) -> [Element] { [first] }

    public static func buildPartialBlock(first: [Element]) -> [Element] { first }

    public static func buildPartialBlock(accumulated: [Element], next: Element) -> [Element] { accumulated + [next] }

    public static func buildPartialBlock(accumulated: [Element], next: [Element]) -> [Element] { accumulated + next }

    /// Empty partial block. Useful for switch cases to represent no elements.
    public static func buildPartialBlock(first: Void) -> [Element] { [] }

    /// Impossible partial block. Useful for fatalError().
    public static func buildPartialBlock(first: Never) -> [Element] {}

    /// Block for an 'if' condition.
    public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }

    /// Block for an 'if' condition which also have an 'else' branch.
    public static func buildEither(first: [Element]) -> [Element] { first }

    /// Block for the 'else' branch of an 'if' condition.
    public static func buildEither(second: [Element]) -> [Element] { second }

    /// Block for an array of elements. Useful for 'for' loops.
    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }

    public static func buildFinalResult(_ components: [Element]) -> SemanticString { .init(components: components) }
}
