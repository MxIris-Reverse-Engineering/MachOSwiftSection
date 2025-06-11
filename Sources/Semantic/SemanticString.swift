public struct SemanticString: Sendable, TextOutputStream {
    private var components: [any SemanticStringComponent] = []

    public var count: Int { components.count }

    public var string: String {
        components.map { $0.string }.joined()
    }

    public init() {}

    public init(components: [any SemanticStringComponent]) {
        self.components = components
    }

    public mutating func append(_ string: String, type: SemanticType) {
        components.append(AnySemanticStringComponent(string: string, type: type))
    }

    public mutating func append(_ semanticString: SemanticString) {
        components.append(contentsOf: semanticString.components)
    }
    
    public mutating func write(_ string: String) {
        write(string, type: .standard)
    }
    
    public mutating func write(_ string: String, type: SemanticType) {
        append(string, type: type)
    }
}
