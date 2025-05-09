/// This is likely to be the primary entry point to this file. Pass a string containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the string to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
public func parseMangledSwiftSymbol(_ mangled: String, isType: Bool = false) throws -> SwiftSymbol {
    return try parseMangledSwiftSymbol(mangled.unicodeScalars, isType: isType)
}

/// Pass a collection of `UnicodeScalars` containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the collection of `UnicodeScalars` to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
public func parseMangledSwiftSymbol<C: Collection>(_ mangled: C, isType: Bool = false, symbolicReferenceResolver: ((Int32, Int) throws -> SwiftSymbol)? = nil) throws -> SwiftSymbol where C.Iterator.Element == UnicodeScalar {
    var demangler = Demangler(scalars: mangled)
    demangler.symbolicReferenceResolver = symbolicReferenceResolver
    if isType {
        return try demangler.demangleType()
    } else if getManglingPrefixLength(mangled) != 0 {
        return try demangler.demangleSymbol()
    } else {
        return try demangler.demangleSwift3TopLevelSymbol()
    }
}
