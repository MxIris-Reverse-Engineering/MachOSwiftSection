import Foundation

public enum NestedFunctions {
    public struct NestedFunctionHolderTest {
        public func outerFunction(parameter: Int) -> Int {
            func innerFunction(inner: Int) -> Int {
                inner * 2
            }

            func secondInnerFunction(first: Int, second: Int) -> Int {
                first + second
            }

            return innerFunction(inner: parameter) + secondInnerFunction(first: parameter, second: parameter)
        }

        public func outerGenericFunction<Element>(element: Element) -> [Element] {
            func innerGenericFunction<Item>(item: Item) -> [Item] {
                [item, item]
            }

            return innerGenericFunction(item: element)
        }

        public func outerWithLocalType() -> Int {
            struct LocalStruct {
                var value: Int
            }

            let local = LocalStruct(value: 42)
            return local.value
        }

        public func outerWithLocalClass() -> String {
            class LocalClass {
                var label: String = ""
            }

            let instance = LocalClass()
            return instance.label
        }
    }
}
