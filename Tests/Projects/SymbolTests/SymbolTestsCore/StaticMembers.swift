import Foundation

public enum StaticMembers {
    public struct StaticMemberStructTest {
        public static let storedConstant: Int = 0
        public static var storedMutable: String = ""
        public static var computedProperty: Int {
            get { 0 }
            set {}
        }

        public static func staticMethod() -> Int { 0 }
        public static func staticGenericMethod<Element>(_ element: Element) -> Element { element }

        public static subscript(index: Int) -> String {
            String(index)
        }
    }

    public class StaticMemberClassTest {
        public static let storedConstant: Int = 0
        public static var storedMutable: String = ""
        public class var classComputed: Int { 0 }

        public static func staticMethod() -> Int { 0 }
        public class func classMethod() -> Int { 0 }

        public init() {}
    }

    public class StaticMemberSubclassTest: StaticMemberClassTest {
        public override class var classComputed: Int { 1 }
        public override class func classMethod() -> Int { 1 }
    }
}
