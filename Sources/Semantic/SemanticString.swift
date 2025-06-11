public struct SemanticString: Sendable, TextOutputStream {
    public private(set) var components: [any SemanticStringComponent] = []

    public var count: Int { components.count }

    public var string: String { components.map { $0.string }.joined() }

    public init() {}

    public init(components: [any SemanticStringComponent]) {
        self.components = components
    }

    public mutating func append(_ string: String, type: SemanticType) {
        components.append(AnyComponent(string: string, type: type))
    }

    public mutating func append(_ semanticString: SemanticString) {
        components.append(contentsOf: semanticString.components)
    }

    public func enumerate(using block: (String, SemanticType) -> Void) {
        components.forEach { block($0.string, $0.type) }
    }
    
    public mutating func write(_ string: String) {
        write(string, type: .standard)
    }

    public mutating func write(_ string: String, type: SemanticType) {
        append(string, type: type)
    }
    
    public func map(_ modifier: (any SemanticStringComponent) -> any SemanticStringComponent) -> SemanticString {
        .init(components: components.map { modifier($0) })
    }
}
