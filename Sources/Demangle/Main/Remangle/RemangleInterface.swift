// Public interface functions for remangling Swift symbols
//
// These convenience functions provide a simple API for remangling demangled nodes
// back into mangled symbol strings.

/// Remangle a node tree with custom options
///
/// - Parameters:
///   - node: The root node of the demangled tree
///   - usePunycode: Whether to use Punycode encoding for non-ASCII identifiers
/// - Returns: The mangled string, or nil if remangling failed
public func mangleAsString(_ node: Node, usePunycode: Bool = true, symbolicReferenceResolver: SymbolicReferenceResolver? = nil) throws(ManglingError) -> String {
    let remangler = Remangler(usePunycode: usePunycode)
    remangler.symbolicReferenceResolver = symbolicReferenceResolver
    return try remangler.mangle(node)
}

// MARK: - Validation Helpers

/// Check if a node tree can be successfully remangled
///
/// - Parameter node: The node to check
/// - Returns: True if the node can be remangled
public func canMangle(_ node: Node) -> Bool {
    return (try? mangleAsString(node)) != nil
}
