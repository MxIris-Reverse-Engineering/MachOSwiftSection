import Foundation

public struct MethodDescriptorFlags: RawRepresentable, Hashable, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private static let kindMask: RawValue = 0x0F
    private static let isInstanceMask: RawValue = 0x10
    private static let isDynamicMask: RawValue = 0x20
    private static let isAsyncMask: RawValue = 0x40
    private static let extraDiscriminatorShift: RawValue = 16
    private static let extraDiscriminatorMask: RawValue = 0xFFFF_0000

    public var kind: MethodDescriptorKind {
        .init(rawValue: .init(rawValue & Self.kindMask))!
    }

    public var isDynamic: Bool {
        rawValue & Self.isDynamicMask != 0
    }

    public var isInstance: Bool {
        rawValue & Self.isInstanceMask != 0
    }

    public var _hasAsyncBitSet: Bool {
        rawValue & Self.isAsyncMask != 0
    }

    public var isAsync: Bool {
        !isCoroutine && _hasAsyncBitSet
    }

    public var isCoroutine: Bool {
        switch kind {
        case .method,
             .`init`,
             .getter,
             .setter:
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

    public var extraDiscriminator: UInt16 {
        .init(rawValue >> Self.extraDiscriminatorShift)
    }
}
