public struct FunctionDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .function(.declaration) }

    public init(_ string: String) {
        self.string = string
    }
}
