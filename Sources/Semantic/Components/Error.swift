public struct Error: SemanticStringComponent, Sendable {
    public private(set) var string: String

    public var type: SemanticType { .error }

    public init(_ string: String) {
        self.string = string
    }
}
