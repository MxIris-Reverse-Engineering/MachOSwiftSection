import Foundation

public enum KeyPaths {
    public struct KeyPathHolderTest {
        public var readOnlyKeyPath: KeyPath<KeyPathHolderTest, Int>
        public var writableKeyPath: WritableKeyPath<KeyPathHolderTest, Int>
        public var referenceWritableKeyPath: ReferenceWritableKeyPath<KeyPathReferenceTest, String>
        public var partialKeyPath: PartialKeyPath<KeyPathHolderTest>
        public var anyKeyPath: AnyKeyPath
        public var value: Int
        public var text: String

        public init(
            readOnlyKeyPath: KeyPath<KeyPathHolderTest, Int>,
            writableKeyPath: WritableKeyPath<KeyPathHolderTest, Int>,
            referenceWritableKeyPath: ReferenceWritableKeyPath<KeyPathReferenceTest, String>,
            partialKeyPath: PartialKeyPath<KeyPathHolderTest>,
            anyKeyPath: AnyKeyPath,
            value: Int,
            text: String
        ) {
            self.readOnlyKeyPath = readOnlyKeyPath
            self.writableKeyPath = writableKeyPath
            self.referenceWritableKeyPath = referenceWritableKeyPath
            self.partialKeyPath = partialKeyPath
            self.anyKeyPath = anyKeyPath
            self.value = value
            self.text = text
        }
    }

    public class KeyPathReferenceTest {
        public var mutableText: String = ""
        public var mutableInteger: Int = 0
        public init() {}
    }

    public struct KeyPathFactoryTest<Root, Value> {
        public var keyPathProducer: (Root) -> KeyPath<Root, Value>

        public init(keyPathProducer: @escaping (Root) -> KeyPath<Root, Value>) {
            self.keyPathProducer = keyPathProducer
        }
    }
}
