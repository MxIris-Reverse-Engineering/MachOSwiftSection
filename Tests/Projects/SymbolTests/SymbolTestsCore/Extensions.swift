import Foundation

public enum Extensions {
    public struct ExtensionBaseStruct<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public struct ExtensionConstrainedStruct<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public protocol ExtensionProtocol {
        associatedtype Item
        var item: Item { get }
    }
}

extension Extensions.ExtensionBaseStruct where Element: Equatable {
    public func isEqualTo(_ other: Self) -> Bool {
        element == other.element
    }
}

extension Extensions.ExtensionBaseStruct where Element: Comparable {
    public func isLessThan(_ other: Self) -> Bool {
        element < other.element
    }
}

extension Extensions.ExtensionBaseStruct where Element: Hashable & Sendable {
    public func computeHash() -> Int {
        element.hashValue
    }
}

extension Extensions.ExtensionConstrainedStruct: Extensions.ExtensionProtocol where Element: Hashable {
    public var item: Element { element }
}

extension Extensions.ExtensionProtocol where Item: Equatable {
    public func matches(_ other: Item) -> Bool {
        item == other
    }
}

extension Extensions.ExtensionProtocol where Item: Comparable {
    public func isLessThan(_ other: Item) -> Bool {
        item < other
    }
}
