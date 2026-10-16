/// A function of an image, bounded by `LC_FUNCTION_STARTS` and the symbol
/// table.
///
/// Every function is scanned, named or not: half of the functions in a
/// macOS 27.2 dyld shared cache carry no symbol, and the calls they make are
/// half of all calls.
public struct CodeFunction: Hashable, Sendable {
    /// Where a function's name came from.
    public enum Name: Hashable, Sendable {
        /// From the symbol table: a mangled Swift name, a C name, or
        /// `-[Class selector]`.
        case symbol(String)
        /// From an Objective-C method list, when the symbol was stripped.
        case objectiveCMethod(className: String, selector: String, isClassMethod: Bool)
        /// From a Swift method descriptor or witness, when the symbol was
        /// stripped.
        case swiftMethod(descriptorAddress: UInt64)
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
