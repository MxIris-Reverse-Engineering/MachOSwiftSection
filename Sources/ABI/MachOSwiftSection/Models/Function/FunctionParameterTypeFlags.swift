import SwiftStdlibToolbox

/// Per-parameter flags in a function type metadata record.
///
/// One word per parameter, present only when
/// ``FunctionTypeFlags/hasParameterFlags`` is set — the compiler omits the
/// whole array when every parameter is an ordinary by-value one.
///
/// Mirrors `swift::TargetParameterTypeFlags`
/// (`swift/ABI/MetadataValues.h`). Prefixed for symmetry with the other
/// function-type flag types, whose ABI names are taken by `Demangling`.
public struct FunctionParameterTypeFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The raw ownership field. Wider than the cases the ABI defines, so a
    /// value outside them is representable and reported here.
    @BitField(bits: 0..<7)
    public var ownershipRawValue: UInt8

    /// How the parameter is passed, or `nil` when the field holds a value
    /// this library does not recognize.
    @BitField(bits: 0..<7)
    public var ownership: FunctionParameterOwnership?

    /// A `T...` parameter.
    @BitField(bits: 7)
    public var isVariadic: Bool

    /// An `@autoclosure` parameter.
    @BitField(bits: 8)
    public var isAutoClosure: Bool

    /// A `@noDerivative` parameter of a differentiable function.
    @BitField(bits: 9)
    public var isNoDerivative: Bool

    /// An `isolated` parameter — the one that carries the actor a function is
    /// isolated to.
    @BitField(bits: 10)
    public var isIsolated: Bool

    /// A `sending` parameter, whose value is transferred across an isolation
    /// boundary.
    @BitField(bits: 11)
    public var isSending: Bool
}
