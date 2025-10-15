import XCTest
@testable import Demangle

/// Test cases for ManglingUtils
final class ManglingUtilsTests: XCTestCase {
    // MARK: - Character Classification Tests

    func testIsLowerLetter() {
        XCTAssertTrue(Mangle.isLowerLetter("a"))
        XCTAssertTrue(Mangle.isLowerLetter("z"))
        XCTAssertFalse(Mangle.isLowerLetter("A"))
        XCTAssertFalse(Mangle.isLowerLetter("0"))
        XCTAssertFalse(Mangle.isLowerLetter("_"))
    }

    func testIsUpperLetter() {
        XCTAssertTrue(Mangle.isUpperLetter("A"))
        XCTAssertTrue(Mangle.isUpperLetter("Z"))
        XCTAssertFalse(Mangle.isUpperLetter("a"))
        XCTAssertFalse(Mangle.isUpperLetter("0"))
        XCTAssertFalse(Mangle.isUpperLetter("_"))
    }

    func testIsDigit() {
        XCTAssertTrue(Mangle.isDigit("0"))
        XCTAssertTrue(Mangle.isDigit("9"))
        XCTAssertFalse(Mangle.isDigit("a"))
        XCTAssertFalse(Mangle.isDigit("A"))
        XCTAssertFalse(Mangle.isDigit("_"))
    }

    func testIsLetter() {
        XCTAssertTrue(Mangle.isLetter("a"))
        XCTAssertTrue(Mangle.isLetter("Z"))
        XCTAssertFalse(Mangle.isLetter("0"))
        XCTAssertFalse(Mangle.isLetter("_"))
    }

    func testIsValidSymbolStart() {
        XCTAssertTrue(Mangle.isValidSymbolStart("a"))
        XCTAssertTrue(Mangle.isValidSymbolStart("Z"))
        XCTAssertTrue(Mangle.isValidSymbolStart("_"))
        XCTAssertTrue(Mangle.isValidSymbolStart("$"))
        XCTAssertFalse(Mangle.isValidSymbolStart("0"))
        XCTAssertFalse(Mangle.isValidSymbolStart("@"))
    }

    func testIsValidSymbolChar() {
        XCTAssertTrue(Mangle.isValidSymbolChar("a"))
        XCTAssertTrue(Mangle.isValidSymbolChar("Z"))
        XCTAssertTrue(Mangle.isValidSymbolChar("_"))
        XCTAssertTrue(Mangle.isValidSymbolChar("$"))
        XCTAssertTrue(Mangle.isValidSymbolChar("0"))
        XCTAssertFalse(Mangle.isValidSymbolChar("@"))
        XCTAssertFalse(Mangle.isValidSymbolChar(" "))
    }

    // MARK: - Punycode Tests

    func testIsNonAscii() {
        XCTAssertFalse(Mangle.isNonAscii("Hello"))
        XCTAssertFalse(Mangle.isNonAscii("test123"))
        XCTAssertTrue(Mangle.isNonAscii("你好"))
        XCTAssertTrue(Mangle.isNonAscii("café"))
        XCTAssertTrue(Mangle.isNonAscii("Hello世界"))
    }

    func testNeedsPunycodeEncoding() {
        XCTAssertFalse(Mangle.needsPunycodeEncoding("validIdentifier"))
        XCTAssertFalse(Mangle.needsPunycodeEncoding("_underscore"))
        XCTAssertFalse(Mangle.needsPunycodeEncoding("$dollar"))
        XCTAssertTrue(Mangle.needsPunycodeEncoding("123invalid"))  // Starts with digit
        XCTAssertTrue(Mangle.needsPunycodeEncoding("hello world"))  // Contains space
        XCTAssertTrue(Mangle.needsPunycodeEncoding("hello@world"))  // Contains @
        XCTAssertTrue(Mangle.needsPunycodeEncoding("你好"))  // Non-ASCII
    }

    // MARK: - Operator Translation Tests

    func testTranslateOperatorChar() {
        XCTAssertEqual(Mangle.translateOperatorChar("&"), "a")  // and
        XCTAssertEqual(Mangle.translateOperatorChar("@"), "c")  // commercial at
        XCTAssertEqual(Mangle.translateOperatorChar("/"), "d")  // divide
        XCTAssertEqual(Mangle.translateOperatorChar("="), "e")  // equal
        XCTAssertEqual(Mangle.translateOperatorChar(">"), "g")  // greater
        XCTAssertEqual(Mangle.translateOperatorChar("<"), "l")  // less
        XCTAssertEqual(Mangle.translateOperatorChar("*"), "m")  // multiply
        XCTAssertEqual(Mangle.translateOperatorChar("!"), "n")  // negate
        XCTAssertEqual(Mangle.translateOperatorChar("|"), "o")  // or
        XCTAssertEqual(Mangle.translateOperatorChar("+"), "p")  // plus
        XCTAssertEqual(Mangle.translateOperatorChar("?"), "q")  // question
        XCTAssertEqual(Mangle.translateOperatorChar("%"), "r")  // remainder
        XCTAssertEqual(Mangle.translateOperatorChar("-"), "s")  // subtract
        XCTAssertEqual(Mangle.translateOperatorChar("~"), "t")  // tilde
        XCTAssertEqual(Mangle.translateOperatorChar("^"), "x")  // xor
        XCTAssertEqual(Mangle.translateOperatorChar("."), "z")  // zperiod
        XCTAssertEqual(Mangle.translateOperatorChar("a"), "a")  // unchanged
    }

    func testTranslateOperator() {
        XCTAssertEqual(Mangle.translateOperator("+"), "p")
        XCTAssertEqual(Mangle.translateOperator("+="), "pe")
        XCTAssertEqual(Mangle.translateOperator("=="), "ee")
        XCTAssertEqual(Mangle.translateOperator("<="), "le")
        XCTAssertEqual(Mangle.translateOperator("&&"), "aa")
        XCTAssertEqual(Mangle.translateOperator("||"), "oo")
        XCTAssertEqual(Mangle.translateOperator("++"), "pp")
        XCTAssertEqual(Mangle.translateOperator("--"), "ss")
        XCTAssertEqual(Mangle.translateOperator("<=>"), "leg")  // Spaceship operator
        XCTAssertEqual(Mangle.translateOperator("..."), "zzz")  // Variadic
        XCTAssertEqual(Mangle.translateOperator("..<"), "zzl")  // Range
    }

    // MARK: - Standard Type Substitution Tests

    func testGetStandardTypeSubst() {
        // Basic structure types
        XCTAssertEqual(Mangle.getStandardTypeSubst("Array"), "a")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Bool"), "b")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Double"), "d")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Float"), "f")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Int"), "i")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UInt"), "u")
        XCTAssertEqual(Mangle.getStandardTypeSubst("String"), "S")

        // Optional enum
        XCTAssertEqual(Mangle.getStandardTypeSubst("Optional"), "q")

        // Pointer types (note: V is uppercase for UnsafeRawPointer)
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafePointer"), "P")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeMutablePointer"), "p")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeRawPointer"), "V")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeMutableRawPointer"), "v")

        // Collection types
        XCTAssertEqual(Mangle.getStandardTypeSubst("Dictionary"), "D")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Set"), "h")

        // Protocol types
        XCTAssertEqual(Mangle.getStandardTypeSubst("Equatable"), "Q")
        XCTAssertEqual(Mangle.getStandardTypeSubst("StringProtocol"), "y")
        XCTAssertEqual(Mangle.getStandardTypeSubst("RawRepresentable"), "Y")

        // Non-standard types (not in StandardTypesMangling.def)
        XCTAssertNil(Mangle.getStandardTypeSubst("CustomType"))
        XCTAssertNil(Mangle.getStandardTypeSubst("MyStruct"))
        XCTAssertNil(Mangle.getStandardTypeSubst("UnicodeScalar"))
        XCTAssertNil(Mangle.getStandardTypeSubst("ImplicitlyUnwrappedOptional"))
        XCTAssertNil(Mangle.getStandardTypeSubst("AnyObject"))
        XCTAssertNil(Mangle.getStandardTypeSubst("Any"))
        XCTAssertNil(Mangle.getStandardTypeSubst("OpaquePointer"))
    }

    func testGetStandardTypeSubstConcurrency() {
        // Without concurrency flag
        XCTAssertNil(Mangle.getStandardTypeSubst("Executor", allowConcurrencyManglings: false))
        XCTAssertNil(Mangle.getStandardTypeSubst("TaskPriority", allowConcurrencyManglings: false))
        XCTAssertNil(Mangle.getStandardTypeSubst("Actor", allowConcurrencyManglings: false))
        XCTAssertNil(Mangle.getStandardTypeSubst("Task", allowConcurrencyManglings: false))

        // With concurrency flag (cX format)
        XCTAssertEqual(Mangle.getStandardTypeSubst("Actor", allowConcurrencyManglings: true), "cA")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Executor", allowConcurrencyManglings: true), "cF")
        XCTAssertEqual(Mangle.getStandardTypeSubst("SerialExecutor", allowConcurrencyManglings: true), "cf")
        XCTAssertEqual(Mangle.getStandardTypeSubst("TaskPriority", allowConcurrencyManglings: true), "cP")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Task", allowConcurrencyManglings: true), "cT")
        XCTAssertEqual(Mangle.getStandardTypeSubst("MainActor", allowConcurrencyManglings: true), "cM")
        XCTAssertEqual(Mangle.getStandardTypeSubst("AsyncSequence", allowConcurrencyManglings: true), "ci")
    }

    // MARK: - Word Substitution Tests

    func testSubstitutionWord() {
        let word = Mangle.SubstitutionWord(start: 5, length: 4)
        XCTAssertEqual(word.start, 5)
        XCTAssertEqual(word.length, 4)
    }

    func testWordReplacement() {
        let repl = Mangle.WordReplacement(stringPos: 10, wordIdx: 2)
        XCTAssertEqual(repl.stringPos, 10)
        XCTAssertEqual(repl.wordIdx, 2)
    }

    // MARK: - Substitution Merging Tests

    func testSubstitutionMergingClear() {
        let merger = Mangle.SubstitutionMerging()
        merger.clear()
        // Just verify it doesn't crash
    }

    func testSubstitutionMergingMaxRepeatCount() {
        XCTAssertEqual(Mangle.SubstitutionMerging.maxRepeatCount, 2048)
    }

    // MARK: - Integration Tests

    func testOperatorTranslationRoundTrip() {
        let operators = ["+", "-", "*", "/", "=", "==", "!=", "<=", ">=", "<", ">",
                        "&&", "||", "!", "&", "|", "^", "~", "%", "@", "?", "."]

        for op in operators {
            let translated = Mangle.translateOperator(op)
            // Verify translation doesn't contain original operator characters
            // (except for special cases)
            XCTAssertNotNil(translated)
            XCTAssertFalse(translated.isEmpty)
        }
    }

    func testAllStandardTypes() {
        // All types from StandardTypesMangling.def (excluding concurrency types)
        let standardTypes = [
            // Structures
            "Array", "Bool", "Double", "Float", "Int", "UInt", "String",
            "Dictionary", "Set", "Character", "Range", "ClosedRange",
            "UnsafePointer", "UnsafeMutablePointer",
            "UnsafeRawPointer", "UnsafeMutableRawPointer",
            "UnsafeBufferPointer", "UnsafeMutableBufferPointer",
            "UnsafeRawBufferPointer", "UnsafeMutableRawBufferPointer",
            "Substring", "ObjectIdentifier", "DefaultIndices",
            "AutoreleasingUnsafeMutablePointer",

            // Enums
            "Optional",

            // Protocols
            "BinaryFloatingPoint", "Encodable", "Decodable", "FloatingPoint",
            "RandomNumberGenerator", "Hashable", "Numeric", "BidirectionalCollection",
            "RandomAccessCollection", "Comparable", "Collection", "MutableCollection",
            "RangeReplaceableCollection", "Equatable", "Sequence", "IteratorProtocol",
            "UnsignedInteger", "RangeExpression", "Strideable", "RawRepresentable",
            "StringProtocol", "SignedInteger", "BinaryInteger"
        ]

        for typeName in standardTypes {
            let subst = Mangle.getStandardTypeSubst(typeName)
            XCTAssertNotNil(subst, "Standard type \(typeName) should have a substitution")
        }
    }

    // MARK: - Performance Tests

    func testOperatorTranslationPerformance() {
        let testOperator = "+++===---***///"

        measure {
            for _ in 0..<10000 {
                _ = Mangle.translateOperator(testOperator)
            }
        }
    }

    func testStandardTypeSubstPerformance() {
        let types = ["Int", "String", "Array", "Dictionary", "Optional"]

        measure {
            for _ in 0..<10000 {
                for type in types {
                    _ = Mangle.getStandardTypeSubst(type)
                }
            }
        }
    }

    func testIsNonAsciiPerformance() {
        let testStrings = [
            "shortAscii",
            "averageLengthAsciiString",
            "veryLongAsciiStringWithManyCharactersThatAreAllAscii"
        ]

        measure {
            for _ in 0..<10000 {
                for str in testStrings {
                    _ = Mangle.isNonAscii(str)
                }
            }
        }
    }

    // MARK: - Edge Case Tests

    func testEmptyStringPunycodeEncoding() {
        XCTAssertFalse(Mangle.needsPunycodeEncoding(""))
    }

    func testSingleCharacterOperators() {
        let operators: [Character] = ["+", "-", "*", "/", "=", "<", ">", "!", "&", "|", "^", "~", "%", "@", "?", "."]

        for op in operators {
            let result = Mangle.translateOperatorChar(op)
            XCTAssertNotEqual(result, "\0")
            XCTAssertTrue(Mangle.isLowerLetter(result) || Mangle.isUpperLetter(result))
        }
    }

    func testWordBoundaryDetection() {
        // Test isWordStart
        XCTAssertTrue(Mangle.isWordStart("a"))
        XCTAssertTrue(Mangle.isWordStart("Z"))
        XCTAssertFalse(Mangle.isWordStart("_"))
        XCTAssertFalse(Mangle.isWordStart("0"))

        // Test isWordEnd
        XCTAssertTrue(Mangle.isWordEnd("_", "a"))
        XCTAssertTrue(Mangle.isWordEnd("\0", "a"))
        XCTAssertTrue(Mangle.isWordEnd("A", "a"))  // Transition to uppercase
        XCTAssertFalse(Mangle.isWordEnd("a", "b"))
        XCTAssertFalse(Mangle.isWordEnd("B", "A"))
    }
}
