import Foundation

public enum DefaultImplementationVariants {
    public protocol BasicDefaultProtocol {
        func required() -> Int
        func withDefault() -> String
        func withDefaultAndGeneric<Element>(_ element: Element) -> Element
    }

    public protocol ConstrainedDefaultProtocol {
        associatedtype Element
        var element: Element { get }
    }
}

extension DefaultImplementationVariants.BasicDefaultProtocol {
    public func withDefault() -> String {
        "default"
    }

    public func withDefaultAndGeneric<Element>(_ element: Element) -> Element {
        element
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Equatable {
    public func isEqualTo(_ other: Element) -> Bool {
        element == other
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Comparable {
    public func isLessThan(_ other: Element) -> Bool {
        element < other
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Hashable & Sendable {
    public func computeHash() -> Int {
        element.hashValue
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: AnyObject {
    public func identityCheck(_ other: Element) -> Bool {
        element === other
    }
}
