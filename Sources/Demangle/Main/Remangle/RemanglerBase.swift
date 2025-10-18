/// Base class for the remangler, providing substitution management and buffering.
///
/// This class implements the core infrastructure needed for remangling:
/// - Hash-based substitution lookup cache
/// - Two-level substitution storage (inline + overflow)
/// - Output buffer management
class RemanglerBase: Mangle.IdentifierMangler {
    // MARK: - Constants

    /// Capacity of the hash-based node hash cache (must be power of 2)
    private static let hashHashCapacity = 512

    /// Maximum number of probes in hash table before giving up
    private static let hashHashMaxProbes = 8

    /// Capacity of inline substitution array (avoids heap allocation for common case)
    private static let inlineSubstCapacity = 16

    // MARK: - Properties

    /// Output buffer for mangled string
    private(set) var buffer: String = ""

    /// Hash table for caching node hashes (avoids expensive recursive computation)
    private var hashHash: [SubstitutionEntry?] = Array(repeating: nil, count: hashHashCapacity)

    /// Inline storage for first 16 substitutions (fast path, no heap allocation)
    private var inlineSubstitutions: [SubstitutionEntry] = []

    /// Overflow storage for substitutions beyond inline capacity
    private var overflowSubstitutions: [SubstitutionEntry: UInt64] = [:]

    // MARK: - Word Substitution Support

    /// Whether to use Punycode encoding for non-ASCII identifiers
    /// Subclasses can override this
    var usePunycode: Bool {
        return true
    }

    /// Maximum number of words to track (matches C++ MaxNumWords = 26)
    static let maxNumWords = 26

    /// List of all words seen so far in the mangled string
    var words: [Mangle.SubstitutionWord] = []

    /// List of word replacements in the current identifier
    var substWordsInIdent: [Mangle.WordReplacement] = []

    // MARK: - Initialization

    init() {
        inlineSubstitutions.reserveCapacity(Self.inlineSubstCapacity)
    }

    // MARK: - Buffer Management

    /// Append a string to the output buffer
    func append(_ string: String) {
        buffer.append(string)
    }

    /// Append a character to the output buffer
    func append(_ char: Character) {
        buffer.append(char)
    }

    /// Append an integer to the output buffer
    func append(_ value: UInt64) {
        buffer.append(String(value))
    }

    /// Reset the buffer to a previous position (index-based)
    func resetBuffer(to position: String.Index) {
        buffer = String(buffer[..<position])
    }

    /// Reset the buffer to a previous position (count-based)
    func resetBuffer(to position: Int) {
        let idx = buffer.index(buffer.startIndex, offsetBy: position)
        buffer = String(buffer[..<idx])
    }

    /// Get current buffer position
    var bufferPosition: String.Index {
        return buffer.endIndex
    }

    /// Clear the buffer
    func clearBuffer() {
        buffer = ""
    }

    // MARK: - Hash Computation

    /// Compute hash for a node, with caching to avoid expensive recursion
    func hashForNode(_ node: Node, treatAsIdentifier: Bool = false) -> Int {
        var hash = 0

        if treatAsIdentifier {
            // Treat as identifier regardless of actual kind
            hash = combineHash(hash, Node.Kind.identifier.hashValue)

            if let text = node.text {
                // Handle operator character translation for operators
                if node.kind.isOperatorKind {
                    for char in text {
                        hash = combineHash(hash, translateOperatorChar(char).hashValue)
                    }
                } else {
                    for char in text {
                        hash = combineHash(hash, char.hashValue)
                    }
                }
            }
        } else {
            // Use actual node kind
            hash = combineHash(hash, node.kind.hashValue)

            // Combine index or text
            if let index = node.index {
                hash = combineHash(hash, Int(index))
            } else if let text = node.text {
                for char in text {
                    hash = combineHash(hash, char.hashValue)
                }
            }

            // Recursively hash children
            for child in node.children {
                let childEntry = entryForNode(child, treatAsIdentifier: treatAsIdentifier)
                hash = combineHash(hash, childEntry.storedHash)
            }
        }

        return hash
    }

    /// Combine two hash values
    private func combineHash(_ currentHash: Int, _ newValue: Int) -> Int {
        return 33 &* currentHash &+ newValue
    }

    /// Translate operator character for hashing
    private func translateOperatorChar(_ char: Character) -> Character {
        switch char {
        case "&": return "a"
        case "@": return "c"
        case "/": return "d"
        case "=": return "e"
        case ">": return "g"
        case "<": return "l"
        case "*": return "m"
        case "!": return "n"
        case "|": return "o"
        case "+": return "p"
        case "?": return "q"
        case "%": return "r"
        case "-": return "s"
        case "~": return "t"
        case "^": return "x"
        case ".": return "z"
        default: return char
        }
    }

    // MARK: - Substitution Entry Creation

    /// Create a SubstitutionEntry for a node, using the hash cache
    func entryForNode(_ node: Node, treatAsIdentifier: Bool = false) -> SubstitutionEntry {
        // Compute hash of node pointer + treatment flag for cache lookup
        let ident = treatAsIdentifier ? 4 : 0
        let nodeHash = nodePointerHash(node) &+ ident

        // Linear probing with limited attempts
        for probe in 0 ..< Self.hashHashMaxProbes {
            let index = (nodeHash &+ probe) & (Self.hashHashCapacity - 1)

            if let cachedEntry = hashHash[index] {
                if cachedEntry.matches(node: node, treatAsIdentifier: treatAsIdentifier) {
                    // Cache hit
                    return cachedEntry
                }
            } else {
                // Cache miss - compute hash and store
                let hash = hashForNode(node, treatAsIdentifier: treatAsIdentifier)
                let entry = SubstitutionEntry(node: node, storedHash: hash, treatAsIdentifier: treatAsIdentifier)
                hashHash[index] = entry
                return entry
            }
        }

        // Hash table full at this location - compute without caching
        let hash = hashForNode(node, treatAsIdentifier: treatAsIdentifier)
        return SubstitutionEntry(node: node, storedHash: hash, treatAsIdentifier: treatAsIdentifier)
    }

    /// Compute a hash from a node pointer (for cache indexing)
    private func nodePointerHash(_ node: Node) -> Int {
        // Use ObjectIdentifier for pointer-like hashing
        let objectId = ObjectIdentifier(node)
        let prime = objectId.hashValue &* 2043

        // Rotate for better distribution (simulate pointer alignment patterns)
        return rotateHash(prime, by: 12)
    }

    /// Rotate hash bits
    private func rotateHash(_ value: Int, by shift: Int) -> Int {
        let bits = MemoryLayout<Int>.size * 8
        return (value >> shift) | (value << (bits - shift))
    }

    // MARK: - Substitution Management

    /// Find a substitution and return its index, or nil if not found
    func findSubstitution(_ entry: SubstitutionEntry) -> UInt64? {
        // First search in inline substitutions (fast path)
        if let index = inlineSubstitutions.firstIndex(of: entry) {
            return UInt64(index)
        }

        // Then search in overflow substitutions
        if let index = overflowSubstitutions[entry] {
            return index
        }

        return nil
    }

    /// Add a substitution to the table
    func addSubstitution(_ entry: SubstitutionEntry) {
        // Don't add duplicate substitutions
        if findSubstitution(entry) != nil {
            return
        }

        if inlineSubstitutions.count < Self.inlineSubstCapacity {
            // Still room in inline storage
            inlineSubstitutions.append(entry)
        } else {
            // Need to use overflow storage
            let index = overflowSubstitutions.count + Self.inlineSubstCapacity
            overflowSubstitutions[entry] = UInt64(index)
        }
    }

    /// Get total number of substitutions
    var substitutionCount: Int {
        return inlineSubstitutions.count + overflowSubstitutions.count
    }

    /// Try to use an existing substitution for a node
    ///
    /// - Parameters:
    ///   - entry: The substitution entry to check
    /// - Returns: true if substitution was found and used, false otherwise
    func trySubstitution(_ entry: SubstitutionEntry) -> Bool {
        guard let index = findSubstitution(entry) else {
            return false
        }

        // Mangle the substitution reference
        if index >= 26 {
            // Large index: "A" + mangleIndex(index - 26)
            append("A")
            mangleIndex(index - 26)
        } else {
            // Small index: "A" + character
            append("A")
            let char = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(index)))
            append(char)
        }
        return true
    }

    // MARK: - Helper Methods

    /// Mangle an index value
    ///
    /// Indices are mangled as:
    /// - 0 -> '_'
    /// - n -> '(n-1)_'
    func mangleIndex(_ value: UInt64) {
        if value == 0 {
            append("_")
        } else {
            append(value &- 1)
            append("_")
        }
    }

    /// Mangle a list separator
    func mangleListSeparator(_ isFirstItem: inout Bool) {
        if isFirstItem {
            append("_")
            isFirstItem = false
        }
    }

    /// Mangle end of list
    func mangleEndOfList(_ isFirstItem: Bool) {
        if isFirstItem {
            append("y")
        }
    }

    // MARK: - Word Substitution Helpers

    /// Check if a character can start a word
    func isWordStart(_ ch: Character) -> Bool {
        return !ch.isNumber && ch != "_" && ch != "\0"
    }

    /// Check if a character (following prevCh) defines the end of a word
    func isWordEnd(_ ch: Character, _ prevCh: Character) -> Bool {
        if ch == "_" || ch == "\0" {
            return true
        }
        if !prevCh.isUppercase && ch.isUppercase {
            return true
        }
        return false
    }

    /// Add a word to the words list
    func addWord(_ word: Mangle.SubstitutionWord) {
        words.append(word)
    }

    /// Add a word replacement to the current identifier
    func addSubstWordInIdent(_ repl: Mangle.WordReplacement) {
        substWordsInIdent.append(repl)
    }

    /// Clear word replacements for the current identifier
    func clearSubstWordsInIdent() {
        substWordsInIdent.removeAll(keepingCapacity: true)
    }
}
