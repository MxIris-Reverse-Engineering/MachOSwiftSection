/// A standard text component with `.standard` semantic type.
///
/// This is the default component type for plain text that doesn't
/// have special semantic meaning.
///
/// Example:
/// ```swift
/// Standard("(")
/// Standard(", ")
/// Standard(")")
/// ```
public struct Standard: AtomicSemanticComponent, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let string: String

    @inlinable
    public var type: SemanticType { .standard }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }

    @inlinable
    public init(stringLiteral value: String) {
        self.string = value
    }

    @inlinable
    public init(stringInterpolation: StringInterpolation) {
        self.string = stringInterpolation.description
    }
}
