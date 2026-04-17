import Foundation

public enum NestedFunctions {
    public struct NestedFunctionHolderTest {
        public func outerWithLocalClass() -> String {
            class LocalClass {
                var label: String = ""
            }

            let instance = LocalClass()
            return instance.label
        }
    }
}
