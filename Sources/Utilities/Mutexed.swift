import Foundation
import Mutex

@propertyWrapper
public struct Mutexed<Value>: Sendable, ~Copyable {
    private let mutex: Mutex<Value>

    public init(wrappedValue: Value) {
        self.mutex = Mutex(wrappedValue)
    }

    public var wrappedValue: Value {
        get {
            mutex.withLock { $0 }
        }
        nonmutating set {
            mutex.withLock { $0 = newValue }
        }
    }
}

@propertyWrapper
public struct WeakMutexed<Value: AnyObject>: Sendable, ~Copyable {
    private struct Box {
        weak var wrappedValue: Value?
    }

    private let mutex: Mutex<Box>

    public init(wrappedValue: Value?) {
        self.mutex = Mutex(.init(wrappedValue: wrappedValue))
    }

    public var wrappedValue: Value? {
        get {
            mutex.withLock { $0.wrappedValue }
        }
        nonmutating set {
            mutex.withLock { $0.wrappedValue = newValue }
        }
    }
}
