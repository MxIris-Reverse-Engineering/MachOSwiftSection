public struct Standard: SemanticStringComponent, ExpressibleByStringInterpolation {
    public private(set) var string: String

    public var type: SemanticType { .standard }

    public init(_ string: String) {
        self.string = string
    }

    public init(stringLiteral value: String) {
        self.string = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.string = stringInterpolation.description
    }
}
