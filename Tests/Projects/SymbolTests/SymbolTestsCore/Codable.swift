import Foundation

public enum CodableTests {
    public struct SynthesizedCodableTest: Codable {
        public var identifier: Int
        public var name: String
        public var optionalValue: Double?

        public init(identifier: Int, name: String, optionalValue: Double?) {
            self.identifier = identifier
            self.name = name
            self.optionalValue = optionalValue
        }
    }

    public struct CustomCodableTest: Codable {
        public var displayName: String
        public var hiddenCount: Int

        private enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case hiddenCount = "count"
        }

        public init(displayName: String, hiddenCount: Int) {
            self.displayName = displayName
            self.hiddenCount = hiddenCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.displayName = try container.decode(String.self, forKey: .displayName)
            self.hiddenCount = try container.decode(Int.self, forKey: .hiddenCount)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(hiddenCount, forKey: .hiddenCount)
        }
    }

    public class CodableClassTest: Codable {
        public var identifier: Int
        public var label: String

        public init(identifier: Int, label: String) {
            self.identifier = identifier
            self.label = label
        }
    }

    public enum CodableEnumTest: Codable {
        case empty
        case withValue(Int)
        case withPair(left: String, right: Int)
    }

    public struct GenericCodableTest<Element: Codable>: Codable {
        public var element: Element
        public var metadata: [String: String]

        public init(element: Element, metadata: [String: String]) {
            self.element = element
            self.metadata = metadata
        }
    }
}
