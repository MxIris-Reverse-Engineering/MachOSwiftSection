import Foundation

public enum ResultBuilderDSL {
    @resultBuilder
    public struct FullResultBuilderTest {
        public static func buildExpression(_ expression: Int) -> [Int] {
            [expression]
        }

        public static func buildExpression(_ expression: [Int]) -> [Int] {
            expression
        }

        public static func buildBlock(_ components: [Int]...) -> [Int] {
            components.flatMap { $0 }
        }

        public static func buildOptional(_ component: [Int]?) -> [Int] {
            component ?? []
        }

        public static func buildEither(first component: [Int]) -> [Int] {
            component
        }

        public static func buildEither(second component: [Int]) -> [Int] {
            component
        }

        public static func buildArray(_ components: [[Int]]) -> [Int] {
            components.flatMap { $0 }
        }

        public static func buildLimitedAvailability(_ component: [Int]) -> [Int] {
            component
        }

        public static func buildFinalResult(_ component: [Int]) -> [Int] {
            component
        }
    }

    @resultBuilder
    public struct GenericResultBuilderTest<Element> {
        public static func buildBlock(_ components: [Element]...) -> [Element] {
            components.flatMap { $0 }
        }

        public static func buildExpression(_ expression: Element) -> [Element] {
            [expression]
        }

        public static func buildOptional(_ component: [Element]?) -> [Element] {
            component ?? []
        }
    }
}
