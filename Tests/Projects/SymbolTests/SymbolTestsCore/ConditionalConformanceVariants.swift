import Foundation

public enum ConditionalConformanceVariants {
    public struct ConditionalContainerTest<Element> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public protocol ConditionalFirstProtocol {}
    public protocol ConditionalSecondProtocol {}
    public protocol ConditionalThirdProtocol {}
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.element == rhs.element
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Hashable where Element: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(element)
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Comparable where Element: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.element < rhs.element
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Sendable where Element: Sendable {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalFirstProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalSecondProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol & ConditionalConformanceVariants.ConditionalSecondProtocol {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalThirdProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol,
      Element: ConditionalConformanceVariants.ConditionalSecondProtocol,
      Element: ConditionalConformanceVariants.ConditionalThirdProtocol {}
