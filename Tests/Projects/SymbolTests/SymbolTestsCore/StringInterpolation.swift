import Foundation

public enum StringInterpolations {
    public struct CustomStringInterpolationTest: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        public var storage: String

        public init(stringLiteral value: String) {
            self.storage = value
        }

        public init(stringInterpolation: StringInterpolation) {
            self.storage = stringInterpolation.accumulator
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            public var accumulator: String

            public init(literalCapacity: Int, interpolationCount: Int) {
                self.accumulator = ""
                self.accumulator.reserveCapacity(literalCapacity + interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) {
                accumulator.append(literal)
            }

            public mutating func appendInterpolation(_ value: Int) {
                accumulator.append(String(value))
            }

            public mutating func appendInterpolation(_ value: String) {
                accumulator.append(value)
            }

            public mutating func appendInterpolation<Value: CustomStringConvertible>(_ value: Value) {
                accumulator.append(value.description)
            }

            public mutating func appendInterpolation(formatted value: Double, precision: Int) {
                accumulator.append(String(format: "%.\(precision)f", value))
            }
        }
    }
}
