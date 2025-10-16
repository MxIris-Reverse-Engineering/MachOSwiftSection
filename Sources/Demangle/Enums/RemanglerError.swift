/// Errors that can occur during remangling operations
public enum RemanglerError: Error, CustomStringConvertible {
    /// Remangling was successful
    case success

    /// The node tree is too complex (exceeds maximum depth)
    case tooComplex(Node?)

    /// Unknown or unsupported node kind
    case badNodeKind(Node?)

    /// Node has multiple children when only one was expected
    case multipleChildNodes(Node?)

    /// Bad nominal type kind
    case badNominalTypeKind(Node?)

    /// Unsupported node kind for this operation
    case unsupportedNodeKind(Node?)

    /// Invalid impl parameter convention
    case invalidImplParameterConvention(Node?)

    /// Invalid generic signature
    case invalidGenericSignature(Node?)

    /// Invalid dependent member type
    case invalidDependentMemberType(Node?)

    /// Missing expected child node
    case missingChildNode(Node?, expectedIndex: Int)

    /// Invalid node structure
    case invalidNodeStructure(Node?, message: String)

    /// Symbolic reference resolver not provided when needed
    case missingSymbolicResolver(Node?)

    /// Unexpected builtin type encountered
    case unexpectedBuiltinType(Node?)

    /// Unexpected builtin vector type encountered
    case unexpectedBuiltinVectorType(Node?)

    /// Generic error with message
    case genericError(String)

    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    public var description: String {
        switch self {
        case .success:
            return "Success"
        case .tooComplex(let node):
            return "Node tree too complex (exceeds max depth)\(nodeInfo(node))"
        case .badNodeKind(let node):
            return "Bad node kind\(nodeInfo(node))"
        case .multipleChildNodes(let node):
            return "Multiple child nodes when only one expected\(nodeInfo(node))"
        case .badNominalTypeKind(let node):
            return "Bad nominal type kind\(nodeInfo(node))"
        case .unsupportedNodeKind(let node):
            return "Unsupported node kind\(nodeInfo(node))"
        case .invalidImplParameterConvention(let node):
            return "Invalid impl parameter convention\(nodeInfo(node))"
        case .invalidGenericSignature(let node):
            return "Invalid generic signature\(nodeInfo(node))"
        case .invalidDependentMemberType(let node):
            return "Invalid dependent member type\(nodeInfo(node))"
        case .missingChildNode(let node, let index):
            return "Missing expected child node at index \(index)\(nodeInfo(node))"
        case .invalidNodeStructure(let node, let message):
            return "Invalid node structure: \(message)\(nodeInfo(node))"
        case .missingSymbolicResolver(let node):
            return "Symbolic reference resolver not provided\(nodeInfo(node))"
        case .unexpectedBuiltinType(let node):
            return "Unexpected builtin type\(nodeInfo(node))"
        case .unexpectedBuiltinVectorType(let node):
            return "Unexpected builtin vector type\(nodeInfo(node))"
        case .genericError(let message):
            return "Error: \(message)"
        }
    }

    private func nodeInfo(_ node: Node?) -> String {
        guard let node = node else { return "" }
        return " (kind: \(node.kind))"
    }
}

/// Result type that can contain either a value or a remangling error
public enum RemanglerResult<T> {
    case success(T)
    case failure(RemanglerError)

    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    public var value: T? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }

    public var error: RemanglerError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }

    public func get() throws -> T {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
