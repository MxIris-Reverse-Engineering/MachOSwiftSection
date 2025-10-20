/// A type for representing the different possible failure conditions when using ScalarScanner
public enum DemanglingError: Error, Sendable {
    /// Attempted to convert the buffer to UnicodeScalars but the buffer contained invalid data
    case utf8ParseError

    case punycodeParseError

    /// The scalar at the specified index doesn't match the expected grammar
    case unexpected(at: Int)

    /// Expected `wanted` at offset `at`
    case matchFailed(wanted: String, at: Int)

    /// Expected numerals at offset `at`
    case expectedInt(at: Int)

    /// Attempted to read `count` scalars from position `at` but hit the end of the sequence
    case endedPrematurely(count: Int, at: Int)

    /// Unable to find search patter `wanted` at or after `after` in the sequence
    case searchFailed(wanted: String, after: Int)

    case integerOverflow(at: Int)

    case unimplementedFeature
    
    case requiredNonOptional
    
    case invalidSwiftMangledName
}
