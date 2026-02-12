/// This is likely to be the primary entry point to this file. Pass a string containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the string to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
public func demangleAsNode(_ mangled: String, isType: Bool = false, symbolicReferenceResolver: DemangleSymbolicReferenceResolver? = nil) throws(DemanglingError) -> Node {
    try demangleAsNode(mangled.unicodeScalars, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
}

/// Pass a collection of `UnicodeScalars` containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the collection of `UnicodeScalars` to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
private func demangleAsNode<C: Collection & Sendable>(_ mangled: C, isType: Bool = false, symbolicReferenceResolver: DemangleSymbolicReferenceResolver? = nil) throws(DemanglingError) -> Node where C.Iterator.Element == UnicodeScalar, C.Index: Sendable {
    var demangler = Demangler(scalars: mangled)
    demangler.symbolicReferenceResolver = symbolicReferenceResolver
    if isType {
        return try demangler.demangleType()
    } else if Demangler.getManglingPrefixLength(mangled) != 0 {
        return try demangler.demangleSymbol()
    } else {
        return try demangler.demangleSwift3TopLevelSymbol()
    }
}

// MARK: - Demangling with Global Cache

/// Demangles a symbol with inline interning into the global `NodeCache`.
///
/// Uses inline interning: nodes are interned at creation time during demangling,
/// eliminating the need for a separate post-processing `intern()` pass.
/// This is more efficient than `demangleAsNode()` + `intern()` because it avoids
/// the O(N) recursive traversal of the completed tree.
///
/// - Parameters:
///   - mangled: The mangled symbol string to demangle.
///   - isType: If true, parses as a type without prefix.
///   - symbolicReferenceResolver: Optional resolver for symbolic references.
/// - Returns: The demangled and interned node.
/// - Throws: `DemanglingError` if demangling fails.
///
/// Example:
/// ```swift
/// // Process multiple symbols with automatic deduplication
/// for symbol in symbols {
///     let node = try demangleAsNodeInterned(symbol)
///     // Identical subtrees will share the same Node instances
/// }
/// print("Unique nodes: \(NodeCache.shared.count)")
///
/// // Clear cache when done
/// NodeCache.shared.clear()
/// ```
public func demangleAsNodeInterned(
    _ mangled: String,
    isType: Bool = false,
    symbolicReferenceResolver: DemangleSymbolicReferenceResolver? = nil
) throws(DemanglingError) -> Node {
    let previous = NodeCache.active
    NodeCache.active = .shared
    defer { NodeCache.active = previous }
    return try demangleAsNode(mangled, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
}

/// Demangles a symbol with inline interning into the specified `NodeCache`.
///
/// - Parameters:
///   - mangled: The mangled symbol string to demangle.
///   - cache: The cache to intern nodes into.
///   - isType: If true, parses as a type without prefix.
///   - symbolicReferenceResolver: Optional resolver for symbolic references.
/// - Returns: The demangled and interned node.
/// - Throws: `DemanglingError` if demangling fails.
public func demangleAsNodeInterned(
    _ mangled: String,
    cache: NodeCache,
    isType: Bool = false,
    symbolicReferenceResolver: DemangleSymbolicReferenceResolver? = nil
) throws(DemanglingError) -> Node {
    let previous = NodeCache.active
    NodeCache.active = cache
    defer { NodeCache.active = previous }
    return try demangleAsNode(mangled, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
}

// MARK: - Batch Demangling

/// Demangles multiple symbols with inline interning into the global `NodeCache`.
///
/// Uses inline interning for efficient deduplication during demangling.
/// Identical subtrees will share the same Node instances.
///
/// - Parameters:
///   - symbols: An array of mangled symbol strings to demangle.
///   - isType: If true, symbols are parsed as types without prefix.
///   - symbolicReferenceResolver: Optional resolver for symbolic references.
/// - Returns: An array of demangled and interned nodes (nil for failed demanglings).
///
/// Example:
/// ```swift
/// let symbols = machO.symbols.map { $0.name }
/// let nodes = demangleBatch(symbols)
/// print("Demangled \(nodes.compactMap { $0 }.count) symbols")
/// print("Unique nodes: \(NodeCache.shared.count)")
/// ```
public func demangleBatch(
    _ symbols: [String],
    isType: Bool = false,
    symbolicReferenceResolver: DemangleSymbolicReferenceResolver? = nil
) -> [Node?] {
    NodeCache.withActive(.shared) {
        symbols.map { symbol in
            try? demangleAsNode(symbol, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
        }
    }
}
