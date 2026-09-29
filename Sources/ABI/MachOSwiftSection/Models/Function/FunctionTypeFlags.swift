import Foundation

public enum FunctionMetadataConvention: UInt8 {
    case swift
    case block
    case thin
    case cFunctionPointer
}

public struct FunctionTypeFlags<IntType: FixedWidthInteger & Sendable>: OptionSet, Equatable, Sendable {
    public typealias RawValue = IntType

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    // swiftformat:disable all
    private enum Constants {
        static var numParametersMask:    RawValue { 0x0000FFFF }
        static var conventionMask:       RawValue { 0x00FF0000 }
        static var conventionShift:      RawValue { 16 }
        static var throwsMask:           RawValue { 0x01000000 }
        static var paramFlagsMask:       RawValue { 0x02000000 }
        static var escapingMask:         RawValue { 0x04000000 }
        static var differentiableMask:   RawValue { 0x08000000 }
        static var globalActorMask:      RawValue { 0x10000000 }
        static var asyncMask:            RawValue { 0x20000000 }
        static var sendableMask:         RawValue { 0x40000000 }
        static var extendedFlagsMask:    RawValue { 0x80000000 }
    }
    // swiftformat:enable all

    public var numberOfParameters: IntType {
        rawValue & Constants.numParametersMask
    }

    public var isAsync: Bool {
        rawValue & Constants.asyncMask != .zero
    }

    public var isThrowing: Bool {
        rawValue & Constants.throwsMask != .zero
    }

    public var isEscaping: Bool {
        rawValue & Constants.escapingMask != .zero
    }

    public var isSendable: Bool {
        rawValue & Constants.sendableMask != .zero
    }

    public var hasParameterFlags: Bool {
        rawValue & Constants.paramFlagsMask != .zero
    }

    public var isDifferentiable: Bool {
        rawValue & Constants.differentiableMask != .zero
    }

    public var hasGlobalActor: Bool {
        rawValue & Constants.globalActorMask != .zero
    }

    public var hasExtendedFlags: Bool {
        rawValue & Constants.extendedFlagsMask != .zero
    }

    public var convention: FunctionMetadataConvention {
        .init(rawValue: UInt8(rawValue))!
    }
}
