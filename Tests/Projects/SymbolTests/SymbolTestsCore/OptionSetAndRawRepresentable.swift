import Foundation

public enum OptionSetAndRawRepresentable {
    public struct OptionSetTest: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let first = OptionSetTest(rawValue: 1 << 0)
        public static let second = OptionSetTest(rawValue: 1 << 1)
        public static let third = OptionSetTest(rawValue: 1 << 2)
        public static let all: OptionSetTest = [.first, .second, .third]
    }

    public struct StringRawRepresentableTest: RawRepresentable {
        public let rawValue: String

        public init?(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public struct IntRawRepresentableTest: RawRepresentable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public struct GenericRawRepresentableTest<Raw: Hashable>: RawRepresentable {
        public var rawValue: Raw

        public init(rawValue: Raw) {
            self.rawValue = rawValue
        }
    }
}
