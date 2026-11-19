import Foundation
import SwiftStdlibToolbox

/// Mirrors `swift::MethodDescriptorFlags` (`swift/ABI/MetadataValues.h`).
public struct MethodDescriptorFlags: RawRepresentable, Hashable, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    /// The kind of method, or `nil` for a kind this reader does not know.
    /// Four bits hold it and six values are defined so far.
    @BitField(bits: 0..<4)
    public var kind: MethodDescriptorKind?

    @BitField(bits: 5)
    public var isDynamic: Bool

    @BitField(bits: 4)
    public var isInstance: Bool

    /// The raw async bit, which means a callee-allocated coroutine on a
    /// coroutine and `async` on anything else.
    @BitField(bits: 6)
    public var _hasAsyncBitSet: Bool

    public var isAsync: Bool {
        !isCoroutine && _hasAsyncBitSet
    }

    /// Whether the method is a coroutine accessor. A kind this reader does
    /// not know is not taken for one.
    public var isCoroutine: Bool {
        switch kind {
        case .method,
             .`init`,
             .getter,
             .setter,
             nil:
            return false
        case .modifyCoroutine,
             .readCoroutine:
            return true
        }
    }

    public var isCalleeAllocatedCoroutine: Bool {
        isCoroutine && _hasAsyncBitSet
    }

    public var isData: Bool {
        isAsync || isCalleeAllocatedCoroutine
    }

    @BitField(bits: 16..<32)
    public var extraDiscriminator: UInt16
}
