import SwiftStdlibToolbox

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

    /// The function declares a concrete error type (`throws(MyError)`), so a
    /// thrown-error type trails the record.
    @BitField(bits: 0)
    public var isTypedThrows: Bool

    /// Three bits holding one isolation kind: 1 is `@isolated(any)` and 2 is
    /// `nonisolated(nonsending)`.
    @BitField(bits: 1..<4)
    private var isolationKind: UInt8

    /// `@isolated(any)`: the function carries its own isolation with it.
    public var isIsolatedAny: Bool {
        isolationKind == 1
    }

    /// `nonisolated(nonsending)`: the function runs on its caller's executor.
    public var isNonIsolatedNonsending: Bool {
        isolationKind == 2
    }

    /// The result is `sending` — transferred across an isolation boundary.
    @BitField(bits: 4)
    public var hasSendingResult: Bool

    /// The set of invertible protocols the function type suppresses
    /// (`~Copyable` and friends), carried in the high 16 bits.
    @BitField(bits: 16..<32)
    public var invertedProtocols: InvertibleProtocolSet
}
