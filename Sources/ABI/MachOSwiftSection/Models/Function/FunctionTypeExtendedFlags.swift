/// The second flag word of a function type metadata record, present only
/// when ``FunctionTypeFlags/hasExtendedFlags`` is set.
///
/// It exists because the first flag word ran out of bits: everything Swift
/// added to function types after the original ABI — typed throws, the
/// isolation kinds, `sending` results, suppressed invertible protocols —
/// lives here.
///
/// Mirrors `swift::TargetExtendedFunctionTypeFlags`
/// (`swift/ABI/MetadataValues.h`).
///
/// Named with a `FunctionType` prefix rather than after the ABI type because
/// `Demangling` vends its own `ExtendedFunctionTypeFlags` — a decoder value
/// type, not this record — and consumers such as `SwiftInspection` import
/// both modules unqualified.
public struct FunctionTypeExtendedFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    private enum Constants {
        static let typedThrowsMask: UInt32 = 0x0000_0001
        /// Three bits holding one of the isolation kinds below.
        static let isolationMask: UInt32 = 0x0000_000E
        static let isolatedAny: UInt32 = 0x0000_0002
        static let nonIsolatedNonsending: UInt32 = 0x0000_0004
        static let hasSendingResultMask: UInt32 = 0x0000_0010
        static let invertedProtocolShift: UInt32 = 16
    }

    /// The function declares a concrete error type (`throws(MyError)`), so a
    /// thrown-error type trails the record.
    public var isTypedThrows: Bool { rawValue & Constants.typedThrowsMask != 0 }

    /// `@isolated(any)`: the function carries its own isolation with it.
    public var isIsolatedAny: Bool {
        rawValue & Constants.isolationMask == Constants.isolatedAny
    }

    /// `nonisolated(nonsending)`: the function runs on its caller's executor.
    public var isNonIsolatedNonsending: Bool {
        rawValue & Constants.isolationMask == Constants.nonIsolatedNonsending
    }

    /// The result is `sending` — transferred across an isolation boundary.
    public var hasSendingResult: Bool {
        rawValue & Constants.hasSendingResultMask != 0
    }

    /// The set of invertible protocols the function type suppresses
    /// (`~Copyable` and friends), carried in the high 16 bits.
    public var invertedProtocols: InvertibleProtocolSet {
        InvertibleProtocolSet(rawValue: UInt16(truncatingIfNeeded: rawValue >> Constants.invertedProtocolShift))
    }
}
