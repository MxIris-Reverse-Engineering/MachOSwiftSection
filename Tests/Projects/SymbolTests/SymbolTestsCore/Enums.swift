import Foundation

public enum Enums {
    public enum MultiPayloadEnumTests {
        case closure(() -> Void)
        case object(NSObject)
        case tuple(a: Int, b: Double)
        case empty
    }

    public enum MultiPayloadEnumTests1 {
        case string(String)
        case data(Data)
        case nsNumber(Decimal)
        case date(Date)
        case url(URL)
        case attributedString(AttributedString)
    }

    public enum MultiPayloadEnumTests2 {
        case string(Swift.String)
        case data(Data)
        case nsNumber(NSNumber)
        case nsNumber1(NSNumber)
        case nsNumber2(NSNumber)
        case nsNumber3(NSNumber)
        case nsNumber4(NSNumber)
        case nsNumber5(NSNumber)
    }

    public enum NoPayloadEnumTest {
        case north
        case south
        case east
        case west
    }

    public enum SinglePayloadEnumTest {
        case value(String)
        case none
        case error
    }

    public indirect enum IndirectEnumTest {
        case leaf(Int)
        case node(IndirectEnumTest, IndirectEnumTest)
    }

    public enum PartialIndirectEnumTest {
        case leaf(Int)
        indirect case node(PartialIndirectEnumTest, PartialIndirectEnumTest)
        indirect case chain(PartialIndirectEnumTest)
    }

    public enum RawValueEnumTest: Int {
        case first = 1
        case second = 2
        case third = 3

        public var description: String {
            switch self {
            case .first: "first"
            case .second: "second"
            case .third: "third"
            }
        }

        public func doubled() -> Int { rawValue * 2 }

        public static func fromString(_ string: String) -> Self? { nil }
    }

    public enum StringRawValueEnumTest: String {
        case hello = "hello"
        case world = "world"
    }

    public enum CaseIterableEnumTest: String, CaseIterable {
        case alpha
        case beta
        case gamma
    }

    @objc
    public enum ObjCEnumTest: Int {
        case first = 1
        case second = 2
        case third = 3
    }
}
