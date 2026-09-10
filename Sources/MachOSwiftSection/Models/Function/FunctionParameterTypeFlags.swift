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

    private enum Constants {
        static let ownershipMask: UInt32 = 0x7F
        static let variadicMask: UInt32 = 0x80
        static let autoClosureMask: UInt32 = 0x100
        static let noDerivativeMask: UInt32 = 0x200
        static let isolatedMask: UInt32 = 0x400
        static let sendingMask: UInt32 = 0x800
    }

    /// The raw ownership field. Wider than the cases the ABI defines, so a
    /// value outside them is representable and reported here.
    public var ownershipRawValue: UInt8 {
        UInt8(truncatingIfNeeded: rawValue & Constants.ownershipMask)
    }

    /// How the parameter is passed, or `nil` when the field holds a value
    /// this library does not recognize.
    public var ownership: FunctionParameterOwnership? {
        FunctionParameterOwnership(rawValue: ownershipRawValue)
    }

    /// A `T...` parameter.
    public var isVariadic: Bool { rawValue & Constants.variadicMask != 0 }

    /// An `@autoclosure` parameter.
    public var isAutoClosure: Bool { rawValue & Constants.autoClosureMask != 0 }

    /// A `@noDerivative` parameter of a differentiable function.
    public var isNoDerivative: Bool { rawValue & Constants.noDerivativeMask != 0 }

    /// An `isolated` parameter — the one that carries the actor a function is
    /// isolated to.
    public var isIsolated: Bool { rawValue & Constants.isolatedMask != 0 }

    /// A `sending` parameter, whose value is transferred across an isolation
    /// boundary.
    public var isSending: Bool { rawValue & Constants.sendingMask != 0 }
}
