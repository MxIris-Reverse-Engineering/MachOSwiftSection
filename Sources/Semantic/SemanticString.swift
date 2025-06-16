public struct SemanticString: Sendable, TextOutputStream, Codable {
    public private(set) var components: [AnyComponent] = []

    public var count: Int { components.count }

    public var string: String { components.map { $0.string }.joined() }

    public init() {}

    public init(@SemanticStringBuilder builder: () -> SemanticString) {
        self = builder()
    }
    
    public init(components: any SemanticStringComponent...) {
        self.components = components.map { .init(component: $0) }
    }
    
    public init(components: [any SemanticStringComponent]) {
        self.components = components.map { .init(component: $0) }
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
    
    public func replacing(from type: SemanticType, to newType: SemanticType) -> SemanticString {
        map { component in
            if component.type == type {
                return AnyComponent(string: component.string, type: newType)
            } else {
                return component
            }
        }
    }
}
