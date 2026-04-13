import Foundation

public enum PropertyObservers {
    public class PropertyObserverClassTest {
        public var observedValue: Int = 0 {
            willSet {
                print("willSet: \(newValue)")
            }
            didSet {
                print("didSet: \(oldValue)")
            }
        }

        public var observedName: String = "" {
            willSet(newName) {
                _ = newName
            }
            didSet(oldName) {
                _ = oldName
            }
        }

        public var computedBacking: Int {
            get { observedValue }
            set { observedValue = newValue }
        }

        public init() {}
    }

    public struct PropertyObserverStructTest {
        public var observedField: Double = 0.0 {
            willSet {
                _ = newValue
            }
            didSet {
                _ = oldValue
            }
        }

        public init() {}
    }
}
