import Foundation

public enum FrozenResilienceContrast {
    @frozen
    public struct FrozenStructTest {
        public var firstField: Int
        public var secondField: Double
        public var thirdField: String

        public init(firstField: Int, secondField: Double, thirdField: String) {
            self.firstField = firstField
            self.secondField = secondField
            self.thirdField = thirdField
        }
    }

    public struct ResilientStructTest {
        public var firstField: Int
        public var secondField: Double
        public var thirdField: String

        public init(firstField: Int, secondField: Double, thirdField: String) {
            self.firstField = firstField
            self.secondField = secondField
            self.thirdField = thirdField
        }
    }

    @frozen
    public enum FrozenEnumContrastTest {
        case empty
        case integer(Int)
        case string(String)
        case pair(Int, Double)
    }

    public enum ResilientEnumContrastTest {
        case empty
        case integer(Int)
        case string(String)
        case pair(Int, Double)
    }

    @frozen
    public struct FrozenGenericTest<Element> {
        public var element: Element
        public var count: Int

        public init(element: Element, count: Int) {
            self.element = element
            self.count = count
        }
    }

    public struct ResilientGenericTest<Element> {
        public var element: Element
        public var count: Int

        public init(element: Element, count: Int) {
            self.element = element
            self.count = count
        }
    }
}
