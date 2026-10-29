/// One type of an Objective-C type encoding, as an Objective-C protocol
/// record spells its methods' and properties' types (evolution proposal
/// `swift-declared-objc-protocols`). The extended encoding a Swift-emitted
/// record carries names classes, protocols and block signatures
/// (`@"NSString"`, `@"<NSCopying>"`, `@?<v@?@"NSError">`); nullability and
/// collection element types are never recorded.
package indirect enum ObjCEncodedType: Sendable, Hashable {
    case void
    /// `B`: `BOOL` on arm64, Swift's `Bool`.
    case bool
    case character
    case unsignedCharacter
    case short
    case unsignedShort
    case int
    case unsignedInt
    /// `l`: a 32-bit `long`, which a 64-bit encoding spells `q`.
    case long
    case unsignedLong
    /// `q`: `NSInteger`, `long` and `long long` alike — and Swift's `Int`.
    case longLong
    /// `Q`: `NSUInteger`, and Swift's `UInt`.
    case unsignedLongLong
    case float
    case double
    case longDouble
    /// `*`
    case characterString
    /// `:`
    case selector
    /// `#`
    case objectClass
    /// `@`, `@"Class"`, `@"<Protocol>"`, `@"Class<Protocol>"`: the class
    /// name is `nil` for `id`.
    case object(className: String?, protocolNames: [String])
    /// `@?`, with its signature when the extended encoding carries one.
    case block(ObjCBlockSignature?)
    /// `^type`; `^?` is a function pointer, read as a pointer to `unknown`.
    case pointer(ObjCEncodedType, isConst: Bool)
    case structure(name: String?)
    case union(name: String?)
    case array(count: Int, element: ObjCEncodedType)
    case bitField(width: Int)
    /// `?`, or what the parser could not read.
    case unknown

    /// Whether the type is an Objective-C object or block — a pointer the
    /// importer makes optional when nothing annotates its nullability.
    package var isObjectPointer: Bool {
        switch self {
        case .object, .block, .objectClass: true
        default: false
        }
    }
}

/// A block's signature: its result and the parameters after the block
/// literal itself.
package struct ObjCBlockSignature: Sendable, Hashable {
    package let returnType: ObjCEncodedType
    package let parameterTypes: [ObjCEncodedType]
}

/// A method's type encoding: its result and the parameters after `self` and
/// `_cmd`.
package struct ObjCMethodTypeEncoding: Sendable, Hashable {
    package let returnType: ObjCEncodedType
    package let parameterTypes: [ObjCEncodedType]
}

/// Reads Objective-C type encodings. Only what the runtime and the compilers
/// write is accepted; anything else reads as `nil` rather than a guess.
package enum ObjCTypeEncodingParser {
    /// A method's encoding (`@"NSString"32@0:8@"NSString"16^@24`), with the
    /// stack offsets skipped.
    package static func methodType(from encoding: String) -> ObjCMethodTypeEncoding? {
        var reader = Reader(encoding)
        guard let returnType = reader.readType() else { return nil }
        reader.skipOffset()
        var argumentTypes: [ObjCEncodedType] = []
        while !reader.isAtEnd {
            guard let argumentType = reader.readType() else { return nil }
            reader.skipOffset()
            argumentTypes.append(argumentType)
        }
        // `self` and `_cmd`.
        guard argumentTypes.count >= 2 else { return nil }
        return ObjCMethodTypeEncoding(returnType: returnType, parameterTypes: Array(argumentTypes.dropFirst(2)))
    }

    /// One type (`@"NSString"`), as a property's `T` attribute spells it.
    package static func type(from encoding: String) -> ObjCEncodedType? {
        var reader = Reader(encoding)
        guard let type = reader.readType(), reader.isAtEnd else { return nil }
        return type
    }

    /// A property's type: the `T` attribute of its attribute string
    /// (`T@"NSString",N,R`).
    package static func propertyType(fromAttributes attributes: String) -> ObjCEncodedType? {
        // The type may itself hold commas (a structure's field list), so it
        // runs to the first comma that follows a complete type.
        guard attributes.hasPrefix("T") else { return nil }
        var reader = Reader(String(attributes.dropFirst()))
        guard let type = reader.readType() else { return nil }
        guard reader.isAtEnd || reader.peek == "," else { return nil }
        return type
    }

    private struct Reader {
        private let characters: [Character]
        private var position = 0

        init(_ text: String) {
            self.characters = Array(text)
        }

        var isAtEnd: Bool {
            position >= characters.count
        }

        var peek: Character? {
            isAtEnd ? nil : characters[position]
        }

        mutating func skipOffset() {
            while let character = peek, character.isNumber || character == "-" {
                position += 1
            }
        }

        mutating func readNumber() -> Int? {
            var digits = ""
            while let character = peek, character.isNumber {
                digits.append(character)
                position += 1
            }
            return Int(digits)
        }

        /// A quoted name (`"NSString"`); the opening quote is next.
        mutating func readQuoted() -> String? {
            guard peek == "\"" else { return nil }
            position += 1
            var name = ""
            while let character = peek, character != "\"" {
                name.append(character)
                position += 1
            }
            guard peek == "\"" else { return nil }
            position += 1
            return name
        }

        mutating func readType() -> ObjCEncodedType? {
            var isConst = false
            while let character = peek, "rnNoORVAj".contains(character) {
                if character == "r" {
                    isConst = true
                }
                position += 1
            }
            guard let character = peek else { return nil }
            position += 1
            switch character {
            case "v": return .void
            case "B": return .bool
            case "c": return .character
            case "C": return .unsignedCharacter
            case "s": return .short
            case "S": return .unsignedShort
            case "i": return .int
            case "I": return .unsignedInt
            case "l": return .long
            case "L": return .unsignedLong
            case "q": return .longLong
            case "Q": return .unsignedLongLong
            case "f": return .float
            case "d": return .double
            case "D": return .longDouble
            case "*": return .characterString
            case ":": return .selector
            case "#": return .objectClass
            case "?": return .unknown
            case "@": return readObject()
            case "^":
                guard let pointee = readType() else { return nil }
                return .pointer(pointee, isConst: isConst)
            case "{": return readAggregate(closing: "}").map { .structure(name: $0) }
            case "(": return readAggregate(closing: ")").map { .union(name: $0) }
            case "[":
                guard let count = readNumber(), let element = readType(), peek == "]" else { return nil }
                position += 1
                return .array(count: count, element: element)
            case "b":
                guard let width = readNumber() else { return nil }
                return .bitField(width: width)
            default:
                return nil
            }
        }

        private mutating func readObject() -> ObjCEncodedType? {
            if peek == "?" {
                position += 1
                guard peek == "<" else { return .block(nil) }
                position += 1
                // The block's own encoding: its result, the block literal,
                // then its parameters. The compilers write no offsets here;
                // any are skipped all the same.
                guard let returnType = readType() else { return nil }
                skipOffset()
                guard readType() != nil else { return nil }
                skipOffset()
                var parameterTypes: [ObjCEncodedType] = []
                while let character = peek, character != ">" {
                    guard let parameterType = readType() else { return nil }
                    skipOffset()
                    parameterTypes.append(parameterType)
                }
                guard peek == ">" else { return nil }
                position += 1
                return .block(ObjCBlockSignature(returnType: returnType, parameterTypes: parameterTypes))
            }
            guard peek == "\"" else { return .object(className: nil, protocolNames: []) }
            guard let quoted = readQuoted() else { return nil }
            // `NSObject<NSCopying><NSCoding>` or `<NSCopying>`.
            var className = ""
            var protocolNames: [String] = []
            var index = quoted.startIndex
            while index < quoted.endIndex, quoted[index] != "<" {
                className.append(quoted[index])
                index = quoted.index(after: index)
            }
            while index < quoted.endIndex {
                guard quoted[index] == "<", let closing = quoted[index...].firstIndex(of: ">") else { return nil }
                protocolNames.append(String(quoted[quoted.index(after: index) ..< closing]))
                index = quoted.index(after: closing)
            }
            return .object(className: className.isEmpty ? nil : className, protocolNames: protocolNames)
        }

        /// A structure or union: its name, with the field list skipped —
        /// which may nest aggregates and quote field names.
        private mutating func readAggregate(closing: Character) -> String?? {
            var name = ""
            while let character = peek, character != "=", character != closing {
                name.append(character)
                position += 1
            }
            var depth = 1
            while let character = peek {
                position += 1
                switch character {
                case "\"":
                    while let quotedCharacter = peek, quotedCharacter != "\"" {
                        position += 1
                    }
                    position += 1
                case "{", "(":
                    depth += 1
                case "}", ")":
                    depth -= 1
                    if depth == 0 {
                        return .some(name.isEmpty || name == "?" ? nil : name)
                    }
                default:
                    break
                }
            }
            return nil
        }
    }
}
