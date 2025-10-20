// Type decoder specific enums

public enum ImplMetatypeRepresentation: Sendable {
    case thin
    case thick
    case objC
}

public enum ImplCoroutineKind: Sendable {
    case none
    case yieldOnce
    case yieldOnce2
    case yieldMany
}

public enum ImplParameterConvention: String, Sendable {
    case indirectIn = "@in"
    case indirectInConstant = "@in_constant"
    case indirectInGuaranteed = "@in_guaranteed"
    case indirectInout = "@inout"
    case indirectInoutAliasable = "@inout_aliasable"
    case directOwned = "@owned"
    case directUnowned = "@unowned"
    case directGuaranteed = "@guaranteed"
    case packOwned = "@pack_owned"
    case packGuaranteed = "@pack_guaranteed"
    case packInout = "@pack_inout"

    public init?(string: String) {
        self.init(rawValue: string)
    }
}

public enum ImplParameterInfoFlags: UInt8, CaseIterable, Sendable {
    case notDifferentiable = 0x1
    case sending = 0x2
    case isolated = 0x4
    case implicitLeading = 0x8
}

public struct ImplParameterInfoOptions: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let notDifferentiable = ImplParameterInfoOptions(rawValue: ImplParameterInfoFlags.notDifferentiable.rawValue)
    public static let sending = ImplParameterInfoOptions(rawValue: ImplParameterInfoFlags.sending.rawValue)
    public static let isolated = ImplParameterInfoOptions(rawValue: ImplParameterInfoFlags.isolated.rawValue)
    public static let implicitLeading = ImplParameterInfoOptions(rawValue: ImplParameterInfoFlags.implicitLeading.rawValue)
}

public enum ImplResultInfoFlags: UInt8, CaseIterable, Sendable {
    case notDifferentiable = 0x1
    case isSending = 0x2
}

public struct ImplResultInfoOptions: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let notDifferentiable = ImplResultInfoOptions(rawValue: ImplResultInfoFlags.notDifferentiable.rawValue)
    public static let isSending = ImplResultInfoOptions(rawValue: ImplResultInfoFlags.isSending.rawValue)
}

public enum ImplResultConvention: String, Sendable {
    case indirect = "@out"
    case owned = "@owned"
    case unowned = "@unowned"
    case unownedInnerPointer = "@unowned_inner_pointer"
    case autoreleased = "@autoreleased"
    case pack = "@pack_out"

    public init?(string: String) {
        self.init(rawValue: string)
    }
}

public enum ImplResultDifferentiability: Sendable {
    case differentiableOrNotApplicable
    case notDifferentiable
}

public enum ImplFunctionRepresentation: Sendable {
    case thick
    case block
    case thin
    case cFunctionPointer
    case method
    case objCMethod
    case witnessMethod
    case closure
}

public enum ImplFunctionDifferentiabilityKind: Sendable {
    case nonDifferentiable
    case forward
    case reverse
    case normal
    case linear
}

// Parameter ownership modes
public enum ParameterOwnership: Sendable {
    case `default`
    case `inout`
    case shared
    case owned
}

// Function metadata convention
public enum FunctionMetadataConvention: Sendable {
    case swift
    case block
    case thin
    case cFunctionPointer
}

// Function metadata differentiability
public enum FunctionMetadataDifferentiabilityKind: Sendable {
    case nonDifferentiable
    case forward
    case reverse
    case normal
    case linear

    public var isDifferentiable: Bool {
        return self != .nonDifferentiable
    }
}

// Extended function type flags
public struct ExtendedFunctionTypeFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let hasIsolatedAny = ExtendedFunctionTypeFlags(rawValue: 1 << 0)
    public static let hasNonIsolatedCaller = ExtendedFunctionTypeFlags(rawValue: 1 << 1)
    public static let hasSendingResult = ExtendedFunctionTypeFlags(rawValue: 1 << 2)
    public static let hasTypedThrows = ExtendedFunctionTypeFlags(rawValue: 1 << 3)

    public func withIsolatedAny() -> ExtendedFunctionTypeFlags {
        return self.union(.hasIsolatedAny)
    }

    public func withNonIsolatedCaller() -> ExtendedFunctionTypeFlags {
        return self.union(.hasNonIsolatedCaller)
    }

    public func withSendingResult() -> ExtendedFunctionTypeFlags {
        return self.union(.hasSendingResult)
    }

    public func withTypedThrows(_ value: Bool) -> ExtendedFunctionTypeFlags {
        if value {
            return self.union(.hasTypedThrows)
        } else {
            return self.subtracting(.hasTypedThrows)
        }
    }
}

// Layout constraint kinds
public enum LayoutConstraintKind: Sendable {
    case unknownLayout
    case refCountedObject
    case nativeRefCountedObject
    case `class`
    case nativeClass
    case trivial
    case bridgeObject
    case trivialOfExactSize
    case trivialOfAtMostSize
    case trivialStride
}

// Requirement kinds
public enum RequirementKind: Sendable {
    case conformance
    case superclass
    case sameType
    case layout
}

// Invertible protocol kinds
public enum InvertibleProtocolKind: UInt32, Sendable {
    case copyable = 0
    case escapable = 1
}
