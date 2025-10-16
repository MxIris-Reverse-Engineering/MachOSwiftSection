import SwiftStdlibToolbox

/// This is likely to be the primary entry point to this file. Pass a string containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the string to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
package func demangleAsNode(_ mangled: String, isType: Bool = false, symbolicReferenceResolver: SymbolicReferenceResolver? = nil) throws -> Node {
//    if let cached = _cache[mangled] {
//        return cached
//    }
    let node = try demangleAsNode(mangled.unicodeScalars, isType: isType, symbolicReferenceResolver: symbolicReferenceResolver)
//    _cache[mangled] = node
    return node
}

/// Pass a collection of `UnicodeScalars` containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the collection of `UnicodeScalars` to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
private func demangleAsNode<C: Collection & Sendable>(_ mangled: C, isType: Bool = false, symbolicReferenceResolver: SymbolicReferenceResolver? = nil) throws -> Node where C.Iterator.Element == UnicodeScalar, C.Index: Sendable {
    var demangler = Demangler(scalars: mangled)
    demangler.symbolicReferenceResolver = symbolicReferenceResolver
    if isType {
        return try demangler.demangleType()
    } else if Demangler.getManglingPrefixLength(mangled) != 0 {
        return try demangler.demangleSymbol()
    } else {
        throw SwiftSymbolParseError.invalidSwiftMangledName
    }
}

@Mutex
private var _cache: [String: Node] = [:]
