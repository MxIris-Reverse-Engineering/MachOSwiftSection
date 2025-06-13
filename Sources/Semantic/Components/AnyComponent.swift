public struct AnyComponent: SemanticStringComponent, Sendable {
    public let string: String

    public let type: SemanticType

    public init(string: String, type: SemanticType) {
        self.string = string
        self.type = type
    }
}
