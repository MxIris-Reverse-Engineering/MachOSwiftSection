// Public interface functions for remangling Swift symbols
//
// These convenience functions provide a simple API for remangling demangled nodes
// back into mangled symbol strings.

/// Remangle a node tree into a mangled string
///
/// - Parameter node: The root node of the demangled tree
/// - Returns: The mangled string, or nil if remangling failed
public func remangle(_ node: Node) throws(RemanglerError) -> String {
    let remangler = Remangler()
    return try remangler.mangle(node)
}

/// Remangle a node tree with custom options
///
/// - Parameters:
///   - node: The root node of the demangled tree
///   - usePunycode: Whether to use Punycode encoding for non-ASCII identifiers
/// - Returns: The mangled string, or nil if remangling failed
public func remangle(_ node: Node, usePunycode: Bool) throws(RemanglerError) -> String {
    let remangler = Remangler(usePunycode: usePunycode)
    return try remangler.mangle(node)
}

// MARK: - Validation Helpers

/// Check if a node tree can be successfully remangled
///
/// - Parameter node: The node to check
/// - Returns: True if the node can be remangled
public func canRemangle(_ node: Node) -> Bool {
    return (try? remangle(node)) != nil
}


// MARK: - Statistics and Debugging

/// Get statistics about a remangling operation
public struct RemanglingStatistics {
    /// The resulting mangled string (nil if failed)
    public let result: String?

    /// Number of substitutions used
    public let substitutionCount: Int

    /// Length of the mangled output
    public let outputLength: Int

    /// Whether remangling succeeded
    public var succeeded: Bool {
        return result != nil
    }
}

/// Remangle a node and collect statistics
///
/// - Parameter node: The node to remangle
/// - Returns: Statistics about the remangling operation
public func remangleWithStatistics(_ node: Node) throws(RemanglerError) -> RemanglingStatistics {
    let remangler = Remangler()
    let result = try remangler.mangle(node)

    return RemanglingStatistics(
        result: result,
        substitutionCount: remangler.substitutionCount,
        outputLength: remangler.buffer.count
    )
}
