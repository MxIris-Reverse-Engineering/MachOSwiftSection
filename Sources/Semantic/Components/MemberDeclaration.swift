public struct MemberDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .memberDeclaration }

    public init(_ string: String) {
        self.string = string
    }
}
