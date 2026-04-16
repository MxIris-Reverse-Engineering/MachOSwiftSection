import Foundation

public enum PropertyWrapperVariants {
    @propertyWrapper
    public struct ProjectedValueWrapperTest<Value> {
        private var storage: Value
        public var wrappedValue: Value {
            get { storage }
            set { storage = newValue }
        }
        public var projectedValue: ProjectedValueWrapperTest<Value> {
            self
        }

        public init(wrappedValue: Value) {
            self.storage = wrappedValue
        }
    }

    @propertyWrapper
    public struct DefaultInitializableWrapperTest {
        public var wrappedValue: Int

        public init() {
            self.wrappedValue = 0
        }

        public init(wrappedValue: Int) {
            self.wrappedValue = wrappedValue
        }
    }

    @propertyWrapper
    public struct StaticSubscriptWrapperTest<Enclosing: AnyObject, Value> {
        public static subscript(
            _enclosingInstance instance: Enclosing,
            wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>,
            storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>
        ) -> Value {
            get {
                instance[keyPath: storageKeyPath].storage
            }
            set {
                instance[keyPath: storageKeyPath].storage = newValue
            }
        }

        @available(*, unavailable)
        public var wrappedValue: Value {
            get { fatalError() }
            set { fatalError() }
        }

        private var storage: Value

        public init(wrappedValue: Value) {
            self.storage = wrappedValue
        }
    }
}
