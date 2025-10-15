/// Utilities for Swift name mangling
///
/// This file provides utility functions and types used by the mangling system,
/// including character classification, operator translation, and word substitution.

// MARK: - Character Classification

enum Mangle {
    /// Returns true if the character is a lowercase letter (a-z)
    @inline(__always)
    static func isLowerLetter(_ ch: Character) -> Bool {
        return ch >= "a" && ch <= "z"
    }

    /// Returns true if the character is an uppercase letter (A-Z)
    @inline(__always)
    static func isUpperLetter(_ ch: Character) -> Bool {
        return ch >= "A" && ch <= "Z"
    }

    /// Returns true if the character is a digit (0-9)
    @inline(__always)
    static func isDigit(_ ch: Character) -> Bool {
        return ch >= "0" && ch <= "9"
    }

    /// Returns true if the character is a letter (a-z or A-Z)
    @inline(__always)
    static func isLetter(_ ch: Character) -> Bool {
        return isLowerLetter(ch) || isUpperLetter(ch)
    }

    /// Returns true if the character defines the begin of a substitution word
    @inline(__always)
    static func isWordStart(_ ch: Character) -> Bool {
        return !isDigit(ch) && ch != "_" && ch != "\0"
    }

    /// Returns true if the character (following prevCh) defines the end of a substitution word
    @inline(__always)
    static func isWordEnd(_ ch: Character, _ prevCh: Character) -> Bool {
        if ch == "_" || ch == "\0" {
            return true
        }

        if !isUpperLetter(prevCh) && isUpperLetter(ch) {
            return true
        }

        return false
    }

    /// Returns true if the character is a valid character which may appear at the start of a symbol mangling
    @inline(__always)
    static func isValidSymbolStart(_ ch: Character) -> Bool {
        return isLetter(ch) || ch == "_" || ch == "$"
    }

    /// Returns true if the character is a valid character which may appear in a symbol mangling
    /// anywhere other than the first character
    @inline(__always)
    static func isValidSymbolChar(_ ch: Character) -> Bool {
        return isValidSymbolStart(ch) || isDigit(ch)
    }

    // MARK: - Punycode Support

    /// Returns true if the string contains any non-ASCII character
    public static func isNonAscii(_ str: String) -> Bool {
        for scalar in str.unicodeScalars {
            if scalar.value >= 0x80 {
                return true
            }
        }
        return false
    }

    /// Returns true if the string contains any character which may not appear in a
    /// mangled symbol string and therefore must be punycode encoded
    public static func needsPunycodeEncoding(_ str: String) -> Bool {
        if str.isEmpty {
            return false
        }

        let first = str.first!
        if !isValidSymbolStart(first) {
            return true
        }

        for ch in str.dropFirst() {
            if !isValidSymbolChar(ch) {
                return true
            }
        }

        return false
    }

    // MARK: - Operator Translation

    /// Translate the given operator character into its mangled form.
    ///
    /// Current operator characters: @/=-+*%<>!&|^~ and the special operator '..'
    public static func translateOperatorChar(_ op: Character) -> Character {
        switch op {
        case "&": return "a"  // 'and'
        case "@": return "c"  // 'commercial at sign'
        case "/": return "d"  // 'divide'
        case "=": return "e"  // 'equal'
        case ">": return "g"  // 'greater'
        case "<": return "l"  // 'less'
        case "*": return "m"  // 'multiply'
        case "!": return "n"  // 'negate'
        case "|": return "o"  // 'or'
        case "+": return "p"  // 'plus'
        case "?": return "q"  // 'question'
        case "%": return "r"  // 'remainder'
        case "-": return "s"  // 'subtract'
        case "~": return "t"  // 'tilde'
        case "^": return "x"  // 'xor'
        case ".": return "z"  // 'zperiod' (the z is silent)
        default: return op
        }
    }

    /// Returns a string where all characters of the operator are translated to their mangled form
    public static func translateOperator(_ op: String) -> String {
        return String(op.map { translateOperatorChar($0) })
    }

    // MARK: - Word Substitution

    /// Describes a word in a mangled identifier
    public struct SubstitutionWord {
        /// The position of the first word character in the mangled string
        public var start: Int

        /// The length of the word
        public var length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// Helper struct which represents a word replacement
    public struct WordReplacement {
        /// The position in the identifier where the word is substituted
        public var stringPos: Int

        /// The index into the mangler's Words array (-1 if invalid)
        public var wordIdx: Int

        public init(stringPos: Int, wordIdx: Int) {
            self.stringPos = stringPos
            self.wordIdx = wordIdx
        }
    }

    // MARK: - Standard Type Substitutions

    /// Returns the standard type kind for an 'S' substitution
    ///
    /// For example, 'i' for "Int", 'S' for "String", etc.
    ///
    /// Based on StandardTypesMangling.def from Swift compiler
    ///
    /// - Parameters:
    ///   - typeName: The Swift type name
    ///   - allowConcurrencyManglings: When true, allows the standard substitutions
    ///     for types in the _Concurrency module that were introduced in Swift 5.5
    /// - Returns: The substitution string if this is a standard type, nil otherwise
    public static func getStandardTypeSubst(_ typeName: String, allowConcurrencyManglings: Bool = true) -> String? {
        // Standard types (Structure, Enum, Protocol)
        switch typeName {
        // Structures
        case "AutoreleasingUnsafeMutablePointer": return "A"  // ObjC interop
        case "Array": return "a"
        case "Bool": return "b"
        case "Dictionary": return "D"
        case "Double": return "d"
        case "Float": return "f"
        case "Set": return "h"
        case "DefaultIndices": return "I"
        case "Int": return "i"
        case "Character": return "J"
        case "ClosedRange": return "N"
        case "Range": return "n"
        case "ObjectIdentifier": return "O"
        case "UnsafePointer": return "P"
        case "UnsafeMutablePointer": return "p"
        case "UnsafeBufferPointer": return "R"
        case "UnsafeMutableBufferPointer": return "r"
        case "String": return "S"
        case "Substring": return "s"
        case "UInt": return "u"
        case "UnsafeRawPointer": return "V"
        case "UnsafeMutableRawPointer": return "v"
        case "UnsafeRawBufferPointer": return "W"
        case "UnsafeMutableRawBufferPointer": return "w"

        // Enums
        case "Optional": return "q"

        // Protocols
        case "BinaryFloatingPoint": return "B"
        case "Encodable": return "E"
        case "Decodable": return "e"
        case "FloatingPoint": return "F"
        case "RandomNumberGenerator": return "G"
        case "Hashable": return "H"
        case "Numeric": return "j"
        case "BidirectionalCollection": return "K"
        case "RandomAccessCollection": return "k"
        case "Comparable": return "L"
        case "Collection": return "l"
        case "MutableCollection": return "M"
        case "RangeReplaceableCollection": return "m"
        case "Equatable": return "Q"
        case "Sequence": return "T"
        case "IteratorProtocol": return "t"
        case "UnsignedInteger": return "U"
        case "RangeExpression": return "X"
        case "Strideable": return "x"
        case "RawRepresentable": return "Y"
        case "StringProtocol": return "y"
        case "SignedInteger": return "Z"
        case "BinaryInteger": return "z"

        default:
            // Concurrency types (Swift 5.5+)
            // These use 'c' prefix: Sc<MANGLING>
            if allowConcurrencyManglings {
                switch typeName {
                case "Actor": return "cA"
                case "CheckedContinuation": return "cC"
                case "UnsafeContinuation": return "cc"
                case "CancellationError": return "cE"
                case "UnownedSerialExecutor": return "ce"
                case "Executor": return "cF"
                case "SerialExecutor": return "cf"
                case "TaskGroup": return "cG"
                case "ThrowingTaskGroup": return "cg"
                case "TaskExecutor": return "ch"
                case "AsyncIteratorProtocol": return "cI"
                case "AsyncSequence": return "ci"
                case "UnownedJob": return "cJ"
                case "MainActor": return "cM"
                case "TaskPriority": return "cP"
                case "AsyncStream": return "cS"
                case "AsyncThrowingStream": return "cs"
                case "Task": return "cT"
                case "UnsafeCurrentTask": return "ct"
                default:
                    return nil
                }
            }
            return nil
        }
    }
    
    protocol Mangler {
        var buffer: String { get }
        func resetBuffer(to position: Int)
        func append(_ string: String)
    }

    // MARK: - Substitution Merging

    /// Utility class for mangling merged substitutions
    ///
    /// Used in the Mangler and Remangler to optimize repeated substitutions.
    /// For example: 'AB' can be merged to 'A2B', 'AB' to 'AbC', etc.
    public class SubstitutionMerging {
        /// The position of the last substitution mangling
        /// e.g. 3 for 'AabC' and 'Aab4C'
        private var lastSubstPosition: Int = 0

        /// The size of the last substitution mangling
        /// e.g. 1 for 'AabC' or 2 for 'Aab4C'
        private var lastSubstSize: Int = 0

        /// The repeat count of the last substitution
        /// e.g. 1 for 'AabC' or 4 for 'Aab4C'
        private var lastNumSubsts: Int = 0

        /// True if the last substitution is an 'S' substitution,
        /// false if the last substitution is an 'A' substitution
        private var lastSubstIsStandardSubst: Bool = false

        /// Maximum number of repeated substitutions
        /// This limit prevents the demangler from blowing up on bogus substitutions
        public static let maxRepeatCount = 2048

        public init() {}

        /// Clear the state
        public func clear() {
            lastNumSubsts = 0
        }

        /// Tries to merge the substitution with a previously mangled substitution
        ///
        /// Returns true on success. In case of false, the caller must mangle the
        /// substitution separately in the form 'S<Subst>' or 'A<Subst>'.
        ///
        /// - Parameters:
        ///   - buffer: Current buffer content
        ///   - subst: The substitution to merge
        ///   - isStandardSubst: True if this is an 'S' substitution, false for 'A'
        ///   - resetBuffer: Callback to reset buffer to a position
        ///   - appendToBuffer: Callback to append string to buffer
        ///   - getBuffer: Callback to get current buffer content
        /// - Returns: True if merge was successful
        public func tryMergeSubst<M: Mangler>(
            _ mangler: M,
            subst: String,
            isStandardSubst: Bool
        ) -> Bool {
            assert(Mangle.isUpperLetter(subst.last!) || (isStandardSubst && Mangle.isLowerLetter(subst.last!)))

            let bufferStr = mangler.buffer

            if lastNumSubsts > 0 && lastNumSubsts < Self.maxRepeatCount
                && bufferStr.count == lastSubstPosition + lastSubstSize
                && lastSubstIsStandardSubst == isStandardSubst {

                // The last mangled thing is a substitution
                assert(lastSubstPosition > 0 && lastSubstPosition < bufferStr.count)
                assert(lastSubstSize > 0)

                let lastSubstStart = bufferStr.index(bufferStr.endIndex, offsetBy: -lastSubstSize)
                var lastSubst = String(bufferStr[lastSubstStart...])

                // Drop leading digits
                while let first = lastSubst.first, Mangle.isDigit(first) {
                    lastSubst = String(lastSubst.dropFirst())
                }

                assert(Mangle.isUpperLetter(lastSubst.last!) || (isStandardSubst && Mangle.isLowerLetter(lastSubst.last!)))

                if lastSubst != subst && !isStandardSubst {
                    // We can merge with a different 'A' substitution
                    // e.g. 'AB' -> 'AbC'
                    lastSubstPosition = bufferStr.count
                    lastNumSubsts = 1
                    let resetPos = bufferStr.count - 1
                    mangler.resetBuffer(to: resetPos)
                    assert(Mangle.isUpperLetter(lastSubst.last!))

                    let lastChar = lastSubst.last!
                    let lowercaseChar = Character(UnicodeScalar(lastChar.asciiValue! - Character("A").asciiValue! + Character("a").asciiValue!))
                    mangler.append(String(lowercaseChar) + subst)
                    lastSubstSize = 1
                    return true
                }

                if lastSubst == subst {
                    // We can merge with the same 'A' or 'S' substitution
                    // e.g. 'AB' -> 'A2B', or 'S3i' -> 'S4i'
                    lastNumSubsts += 1
                    mangler.resetBuffer(to: lastSubstPosition)
                    mangler.append("\(lastNumSubsts)\(subst)")

                    // Get updated buffer to calculate the new size
                    let currentBuffer = mangler.buffer
                    lastSubstSize = currentBuffer.count - lastSubstPosition
                    return true
                }
            }

            // We can't merge with the previous substitution, but let's remember this
            // substitution which will be mangled by the caller
            lastSubstPosition = bufferStr.count + 1
            lastSubstSize = subst.count
            lastNumSubsts = 1
            lastSubstIsStandardSubst = isStandardSubst
            return false
        }
    }

    // MARK: - Identifier Mangling with Word Substitution

    /// Protocol that manglers must implement to use mangleIdentifier
    public protocol IdentifierMangler {
        var words: [SubstitutionWord] { get set }
        var substWordsInIdent: [WordReplacement] { get set }
        var usePunycode: Bool { get }
        var maxNumWords: Int { get }

        func getBufferStr() -> String
        func appendToBuffer(_ str: String)
        func addWord(_ word: SubstitutionWord)
        func addSubstWord(_ repl: WordReplacement)
    }

    /// Mangles an identifier using word substitution
    ///
    /// This is a complex algorithm that:
    /// 1. Searches for common words in the identifier
    /// 2. Replaces repeated words with single-letter substitutions (a-z)
    /// 3. Handles Punycode encoding for non-ASCII identifiers
    ///
    /// - Parameters:
    ///   - mangler: The mangler instance implementing IdentifierMangler protocol
    ///   - ident: The identifier to mangle
    public static func mangleIdentifier<M: IdentifierMangler>(_ mangler: inout M, _ ident: String) {
        let wordsInBuffer = mangler.words.count
        assert(mangler.substWordsInIdent.isEmpty)

        // Handle Punycode encoding for non-ASCII identifiers
        if mangler.usePunycode && needsPunycodeEncoding(ident) {
            if let encoded = Punycode.encodePunycode(ident, mapNonSymbolChars: true) {
                let pcIdent = encoded
                mangler.appendToBuffer("00\(pcIdent.count)")
                if let first = pcIdent.first, (isDigit(first) || first == "_") {
                    mangler.appendToBuffer("_")
                }
                mangler.appendToBuffer(pcIdent)
                return
            }
        }

        // Search for word substitutions and new words
        let notInsideWord = -1
        var wordStartPos = notInsideWord

        for pos in 0...ident.count {
            let ch: Character = pos < ident.count ? ident[ident.index(ident.startIndex, offsetBy: pos)] : "\0"

            if wordStartPos != notInsideWord && isWordEnd(ch, pos > 0 ? ident[ident.index(ident.startIndex, offsetBy: pos - 1)] : "\0") {
                // End of a word
                assert(pos > wordStartPos)
                let wordLen = pos - wordStartPos
                let wordStart = ident.index(ident.startIndex, offsetBy: wordStartPos)
                let wordEnd = ident.index(wordStart, offsetBy: wordLen)
                let word = String(ident[wordStart..<wordEnd])

                // Look up word in buffer and existing words
                func lookupWord(in str: String, from: Int, to: Int) -> Int? {
                    for idx in from..<to {
                        let w = mangler.words[idx]
                        let existingWordStart = str.index(str.startIndex, offsetBy: w.start)
                        let existingWordEnd = str.index(existingWordStart, offsetBy: w.length)
                        let existingWord = String(str[existingWordStart..<existingWordEnd])
                        if word == existingWord {
                            return idx
                        }
                    }
                    return nil
                }

                // Check if word exists in buffer
                var wordIdx = lookupWord(in: mangler.getBufferStr(), from: 0, to: wordsInBuffer)

                // Check if word exists in this identifier
                if wordIdx == nil {
                    wordIdx = lookupWord(in: ident, from: wordsInBuffer, to: mangler.words.count)
                }

                if let idx = wordIdx {
                    // Found word substitution
                    assert(idx < 26)
                    mangler.addSubstWord(WordReplacement(stringPos: wordStartPos, wordIdx: idx))
                } else if wordLen >= 2 && mangler.words.count < mangler.maxNumWords {
                    // New word
                    mangler.addWord(SubstitutionWord(start: wordStartPos, length: wordLen))
                }

                wordStartPos = notInsideWord
            }

            if wordStartPos == notInsideWord && isWordStart(ch) {
                // Begin of a word
                wordStartPos = pos
            }
        }

        // Mangle with word substitutions
        if !mangler.substWordsInIdent.isEmpty {
            mangler.appendToBuffer("0")
        }

        var pos = 0
        var wordsInBufferMutable = wordsInBuffer

        // Add dummy word at end
        mangler.addSubstWord(WordReplacement(stringPos: ident.count, wordIdx: -1))

        for idx in 0..<mangler.substWordsInIdent.count {
            let repl = mangler.substWordsInIdent[idx]

            if pos < repl.stringPos {
                // Mangle substring up to next word substitution
                var first = true
                mangler.appendToBuffer("\(repl.stringPos - pos)")

                while pos < repl.stringPos {
                    // Update start position of new words
                    if wordsInBufferMutable < mangler.words.count
                        && mangler.words[wordsInBufferMutable].start == pos {
                        var word = mangler.words[wordsInBufferMutable]
                        word.start = mangler.getBufferStr().count
                        mangler.words[wordsInBufferMutable] = word
                        wordsInBufferMutable += 1
                    }

                    let ch = ident[ident.index(ident.startIndex, offsetBy: pos)]

                    // Error recovery for invalid identifiers
                    if first && isDigit(ch) {
                        mangler.appendToBuffer("X")
                    } else {
                        mangler.appendToBuffer(String(ch))
                    }

                    pos += 1
                    first = false
                }
            }

            // Handle word substitution
            if repl.wordIdx >= 0 {
                assert(repl.wordIdx <= wordsInBufferMutable)
                pos += mangler.words[repl.wordIdx].length

                if idx < mangler.substWordsInIdent.count - 2 {
                    // Lowercase letter
                    let ch = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(repl.wordIdx)))
                    mangler.appendToBuffer(String(ch))
                } else {
                    // Last word substitution is uppercase
                    let ch = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(repl.wordIdx)))
                    mangler.appendToBuffer(String(ch))
                    if pos == ident.count {
                        mangler.appendToBuffer("0")
                    }
                }
            }
        }

        mangler.substWordsInIdent.removeAll()
    }
}
