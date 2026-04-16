import Foundation

public enum CustomLiterals {
    public struct IntegerLiteralTest: ExpressibleByIntegerLiteral {
        public let value: Int64
        public init(integerLiteral value: Int64) {
            self.value = value
        }
    }

    public struct StringLiteralTest: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
        public let value: String

        public init(stringLiteral value: String) {
            self.value = value
        }

        public init(unicodeScalarLiteral value: String) {
            self.value = value
        }

        public init(extendedGraphemeClusterLiteral value: String) {
            self.value = value
        }
    }

    public struct ArrayLiteralTest: ExpressibleByArrayLiteral {
        public let elements: [Int]

        public init(arrayLiteral elements: Int...) {
            self.elements = elements
        }
    }

    public struct DictionaryLiteralTest: ExpressibleByDictionaryLiteral {
        public let elements: [String: Int]

        public init(dictionaryLiteral elements: (String, Int)...) {
            var dictionary: [String: Int] = [:]
            for (key, value) in elements {
                dictionary[key] = value
            }
            self.elements = dictionary
        }
    }

    public struct BooleanLiteralTest: ExpressibleByBooleanLiteral {
        public let value: Bool
        public init(booleanLiteral value: Bool) {
            self.value = value
        }
    }

    public struct FloatLiteralTest: ExpressibleByFloatLiteral {
        public let value: Double
        public init(floatLiteral value: Double) {
            self.value = value
        }
    }

    public struct NilLiteralTest: ExpressibleByNilLiteral {
        public init(nilLiteral: ()) {}
    }
}
