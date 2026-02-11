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

/// Demangles a symbol and interns the result into the global `NodeCache`.
///
/// Use this when you want automatic deduplication of node trees across
/// multiple demangle calls. The global cache persists until explicitly cleared.
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
    let node = try demangleAsNode(mangled, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
    return NodeCache.shared.intern(node)
}

// MARK: - Batch Demangling

/// Demangles multiple symbols and interns them into the global `NodeCache`.
///
/// This is optimized for processing large numbers of symbols (e.g., all symbols
/// in a binary). Identical subtrees will share the same Node instances.
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
    symbols.map { symbol in
        try? demangleAsNodeInterned(symbol, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
    }
}
