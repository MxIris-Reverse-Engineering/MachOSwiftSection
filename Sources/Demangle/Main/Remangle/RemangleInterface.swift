// Public interface functions for remangling Swift symbols
//
// These convenience functions provide a simple API for remangling demangled nodes
// back into mangled symbol strings.

/// Remangle a node tree into a mangled string
///
/// - Parameter node: The root node of the demangled tree
/// - Returns: The mangled string, or nil if remangling failed
public func remangle(_ node: Node) -> String? {
    let remangler = Remangler()
    let result = remangler.mangle(node)
    return result.value
}

/// Remangle a node tree into a mangled string (throwing version)
///
/// - Parameter node: The root node of the demangled tree
/// - Returns: The mangled string
/// - Throws: RemanglerError if remangling fails
public func remangleThrows(_ node: Node) throws -> String {
    let remangler = Remangler()
    return try remangler.mangleThrows(node)
}

/// Remangle a node tree with custom options
///
/// - Parameters:
///   - node: The root node of the demangled tree
///   - usePunycode: Whether to use Punycode encoding for non-ASCII identifiers
/// - Returns: The mangled string, or nil if remangling failed
public func remangle(_ node: Node, usePunycode: Bool) -> String? {
    let remangler = Remangler(usePunycode: usePunycode)
    let result = remangler.mangle(node)
    return result.value
}

/// Round-trip a mangled symbol: demangle then remangle
///
/// This is useful for testing and validation purposes.
///
/// - Parameter mangledName: The mangled symbol name
/// - Returns: The remangled string, or nil if any step failed
public func roundTrip(_ mangledName: String) -> String? {
    // Demangle
    guard let node = try? demangleAsNode(mangledName) else {
        return nil
    }

    // Remangle
    return remangle(node)
}

/// Verify that a mangled name can be successfully round-tripped
///
/// - Parameter mangledName: The mangled symbol name
/// - Returns: True if demangle->remangle produces the same string
public func canRoundTrip(_ mangledName: String) -> Bool {
    guard let remangled = roundTrip(mangledName) else {
        return false
    }
    return remangled == mangledName
}

/// Extract and remangle a subtree of a demangled node
///
/// This is useful for extracting specific parts of a mangled symbol,
/// such as just the type information.
///
/// - Parameters:
///   - node: The root node to search
///   - predicate: A predicate to find the desired subtree
/// - Returns: The remangled subtree, or nil if not found or remangling failed
public func extractAndRemangle(_ node: Node, where predicate: (Node) -> Bool) -> String? {
    // Find the subtree
    func findNode(_ current: Node) -> Node? {
        if predicate(current) {
            return current
        }
        for child in current.children {
            if let found = findNode(child) {
                return found
            }
        }
        return nil
    }

    guard let subtree = findNode(node) else {
        return nil
    }

    // Remangle it
    return remangle(subtree)
}

/// Modify a demangled tree and remangle it
///
/// This allows you to transform parts of a demangled symbol tree
/// and produce a new mangled name.
///
/// - Parameters:
///   - node: The root node to modify
///   - transform: A transformation function applied to the tree
/// - Returns: The remangled string after transformation, or nil if failed
public func modifyAndRemangle(_ node: Node, transform: (Node) -> Node) -> String? {
    let modifiedNode = transform(node)
    return remangle(modifiedNode)
}

// MARK: - Batch Operations

/// Remangle multiple nodes in batch
///
/// - Parameter nodes: Array of nodes to remangle
/// - Returns: Array of remangled strings (nil for failed items)
public func remangleBatch(_ nodes: [Node]) -> [String?] {
    return nodes.map { remangle($0) }
}

/// Remangle multiple nodes concurrently
///
/// - Parameter nodes: Array of nodes to remangle
/// - Returns: Array of remangled strings (nil for failed items)
public func remangleConcurrent(_ nodes: [Node]) async -> [String?] {
    await withTaskGroup(of: (Int, String?).self) { group in
        for (index, node) in nodes.enumerated() {
            group.addTask {
                (index, remangle(node))
            }
        }

        var results = [String?](repeating: nil, count: nodes.count)
        for await (index, result) in group {
            results[index] = result
        }
        return results
    }
}

// MARK: - Validation Helpers

/// Check if a node tree can be successfully remangled
///
/// - Parameter node: The node to check
/// - Returns: True if the node can be remangled
public func canRemangle(_ node: Node) -> Bool {
    return remangle(node) != nil
}

/// Get detailed error information when remangling fails
///
/// - Parameter node: The node to remangle
/// - Returns: Either the mangled string or an error
public func remangleWithError(_ node: Node) -> RemanglerResult<String> {
    let remangler = Remangler()
    return remangler.mangle(node)
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
public func remangleWithStatistics(_ node: Node) -> RemanglingStatistics {
    let remangler = Remangler()
    let result = remangler.mangle(node)

    return RemanglingStatistics(
        result: result.value,
        substitutionCount: remangler.substitutionCount,
        outputLength: remangler.buffer.count
    )
}
