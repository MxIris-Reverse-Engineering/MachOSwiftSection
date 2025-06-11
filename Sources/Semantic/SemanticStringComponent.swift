public protocol SemanticStringComponent: Sendable {
    var string: String { get }
    var type: SemanticType { get }
}
