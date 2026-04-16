import Foundation

public enum Attributes {
    @propertyWrapper
    public struct PropertyWrapperStruct<Value: Comparable> {
        public var wrappedValue: Value
        public var projectedValue: ClosedRange<Value>

        public init(wrappedValue: Value, range: ClosedRange<Value>) {
            self.projectedValue = range
            self.wrappedValue = min(max(wrappedValue, range.lowerBound), range.upperBound)
        }
    }

    @resultBuilder
    public struct ResultBuilderStruct<Element> {
        public static func buildBlock(_ components: Element...) -> [Element] { components }
        public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }
    }

    @dynamicMemberLookup
    public struct DynamicMemberLookupStruct {
        public subscript(dynamicMember member: String) -> Int { 0 }
    }

    @dynamicCallable
    public struct DynamicCallableStruct {
        public func dynamicallyCall(withArguments arguments: [Int]) -> Int {
            arguments.reduce(0, +)
        }

        public func dynamicallyCall(withKeywordArguments arguments: KeyValuePairs<String, Int>) -> Int { 0 }
    }

    public class ObjCAttributeClass: NSObject {
        @objc public func objcMethod() {}
        @nonobjc public func nonobjcMethod() {}
        @objc public dynamic func objcDynamicMethod() {}
    }
}
