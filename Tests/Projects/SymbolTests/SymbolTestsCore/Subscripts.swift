public enum Subscripts {
    public struct SubscriptGetSetTest {
        public subscript(index: Int) -> Int {
            get { index }
            set { _ = newValue }
        }
    }

    public struct SubscriptMultiParamTest {
        public subscript(row: Int, column: Int) -> Int {
            row * 10 + column
        }
    }

    public struct SubscriptStaticTest {
        public static subscript(index: Int) -> String {
            String(index)
        }
    }

    public class ClassSubscriptTest {
        private var elements: [Int] = []

        public subscript(index: Int) -> Int {
            get { elements.isEmpty ? 0 : elements[index] }
            set { elements.append(newValue) }
        }
    }

    public struct SubscriptGenericTest<Element> {
        public subscript<Key: Hashable>(key: Key) -> Element? {
            nil
        }
    }

    public struct SubscriptStringKeyTest {
        private var storage: [String: Int] = [:]

        public subscript(key: String) -> Int? {
            get { storage[key] }
            set { storage[key] = newValue }
        }
    }
}
