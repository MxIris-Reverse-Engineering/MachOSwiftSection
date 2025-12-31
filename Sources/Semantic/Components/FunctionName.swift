/// A function name component with `.function(.name)` semantic type.
///
/// Example:
/// ```swift
/// FunctionName("doSomething")
/// FunctionName("init")
/// ```
public struct FunctionName: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .function(.name) }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
