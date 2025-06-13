public struct Comment: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .comment }

    public init(_ string: String) {
        self.string = "// \(string)"
    }
}

public struct InlineComment: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .comment }

    public init(_ string: String) {
        self.string = "/* \(string) */"
    }
}

public struct MultipleLineComment: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .comment }

    public init(_ string: String) {
        self.string = "/*\n\(string)\n*/"
    }
}
