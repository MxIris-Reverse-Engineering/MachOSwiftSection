/// A function declaration component with `.function(.declaration)` semantic type.
///
/// Example:
/// ```swift
/// FunctionDeclaration("doSomething")
/// FunctionDeclaration("init")
/// ```
public struct FunctionDeclaration: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .function(.declaration) }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
