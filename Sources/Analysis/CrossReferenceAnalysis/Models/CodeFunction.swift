/// A function of an image, bounded by `LC_FUNCTION_STARTS` and the symbol
/// table.
///
/// Every function is scanned, named or not: half of the functions in a
/// macOS 27.2 dyld shared cache carry no symbol, and the calls they make are
/// half of all calls.
public struct CodeFunction: Hashable, Sendable {
    /// Where a function's name came from, in the order they are tried.
    public enum Name: Hashable, Sendable {
        /// From the symbol table or the export trie, as they spell it: a
        /// mangled Swift name, a C name, or `-[Class selector]`.
        case symbol(String)
        /// From an Objective-C method list, when no symbol names the
        /// function. The method lists do not record categories, so a
        /// category method reads as `-[NSTextView draggingUpdated:]` where
        /// the symbol would say `-[NSTextView(NSDragging) draggingUpdated:]`.
        case objectiveCMethod(className: String, selector: String, isClassMethod: Bool)
        /// A Swift mangled name rebuilt from metadata, when no symbol names
        /// the function: a type's metadata accessor (`…Ma`) or singleton
        /// completion function (`…Mr`), or a method whose descriptor's
        /// `…Tq` symbol spells it. Demangles like a symbol.
        case swiftMetadata(mangledName: String)
    }

    /// The first instruction.
    public let location: CodeLocation
    /// Bytes up to the next function start, or to the end of `__text`.
    public let size: Int
    /// `nil` when neither a symbol nor metadata names the function. An
    /// iOS device's shared cache keeps its images' local symbol entries but
    /// names every one `<redacted>`; those count as unnamed.
    public let name: Name?
    /// Other symbols at the same address, left there by identical code
    /// folding.
    public let foldedSymbolNames: [String]
    /// A function that only manages memory or values — a retain, an
    /// outlined copy — and is hidden from results by default.
    public let isRuntimeHelper: Bool

    public init(location: CodeLocation, size: Int, name: Name?, foldedSymbolNames: [String], isRuntimeHelper: Bool) {
        self.location = location
        self.size = size
        self.name = name
        self.foldedSymbolNames = foldedSymbolNames
        self.isRuntimeHelper = isRuntimeHelper
    }
}
