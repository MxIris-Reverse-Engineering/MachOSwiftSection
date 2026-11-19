import Foundation
import SwiftStdlibToolbox

public enum FunctionMetadataConvention: UInt8 {
    case swift
    case block
    case thin
    case cFunctionPointer
}

/// Mirrors `swift::TargetFunctionTypeFlags` (`swift/ABI/MetadataValues.h`).
public struct FunctionTypeFlags<IntType: FixedWidthInteger & Sendable>: OptionSet, Equatable, Sendable {
    public typealias RawValue = IntType

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<16)
    public var numberOfParameters: IntType

    @BitField(bits: 29)
    public var isAsync: Bool

    @BitField(bits: 24)
    public var isThrowing: Bool

    @BitField(bits: 26)
    public var isEscaping: Bool

    @BitField(bits: 30)
    public var isSendable: Bool

    @BitField(bits: 25)
    public var hasParameterFlags: Bool

    @BitField(bits: 27)
    public var isDifferentiable: Bool

    @BitField(bits: 28)
    public var hasGlobalActor: Bool

    @BitField(bits: 31)
    public var hasExtendedFlags: Bool

    /// The calling convention, or `nil` for one this reader does not know.
    @BitField(bits: 16..<24)
    public var convention: FunctionMetadataConvention?
}
