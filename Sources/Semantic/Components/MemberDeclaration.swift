public struct MemberDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .member(.declaration) }

    public init(_ string: String) {
        self.string = string
    }
}
