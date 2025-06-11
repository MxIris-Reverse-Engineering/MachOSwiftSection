public struct MemberName: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .memberName }

    public init(_ string: String) {
        self.string = string
    }
}
