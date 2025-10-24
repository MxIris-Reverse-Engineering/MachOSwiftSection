/// An error that occurred while looking up a type at runtime from a mangled name.
///
/// This provides a string description of the error that occurred during type lookup or decoding.
public struct TypeLookupError: Error, CustomStringConvertible, Sendable {
    private let message: String
    private let file: String
    private let line: Int

    /// Initialize a type lookup error with a message and source location
    public init(_ message: String, file: String = #file, line: Int = #line) {
        self.message = message
        self.file = file
        self.line = line
    }

    /// Initialize a type lookup error with a formatted message
    public init(format: String, args: CVarArg..., file: String = #file, line: Int = #line) {
        self.message = String(format: format, arguments: args)
        self.file = file
        self.line = line
    }

    /// Initialize from a node error
    public init(node: Node, message: String, file: String = #file, line: Int = #line) {
        let nodeInfo = "Node kind \(node.kind)"
        let textInfo = node.hasText ? " \"\(node.text ?? "")\"" : ""
        self.message = "\(nodeInfo)\(textInfo) - \(message)"
        self.file = file
        self.line = line
    }

    public var description: String {
        return "TypeLookupError at \(file):\(line): \(message)"
    }

    /// Just the error message without file/line info
    public var errorMessage: String {
        return message
    }
}

/// Result type for type decoding operations
public typealias TypeLookupErrorOr<T> = Result<T, TypeLookupError>

extension Result where Failure == TypeLookupError {
    /// Get the value if successful, nil otherwise
    public var value: Success? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }

    /// Check if this result is an error
    public var isError: Bool {
        switch self {
        case .success:
            return false
        case .failure:
            return true
        }
    }

    /// Get the error if present
    public var error: TypeLookupError? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}
