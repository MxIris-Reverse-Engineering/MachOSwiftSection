public struct AnyComponent: SemanticStringComponent, Codable, Sendable {
    public let string: String

    public let type: SemanticType

    public init(string: String, type: SemanticType) {
        self.string = string
        self.type = type
    }

    public init(component: any SemanticStringComponent) {
        self.string = component.string
        self.type = component.type
    }
}
