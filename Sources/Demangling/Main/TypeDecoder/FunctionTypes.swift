/// Describe a function parameter, parameterized on the type representation.
public struct FunctionParam<BuiltType> {
    public var label: String?
    public var type: BuiltType
    public var flags: ParameterFlags

    public init(type: BuiltType) {
        self.type = type
        self.flags = ParameterFlags()
    }

    private init(label: String?, type: BuiltType, flags: ParameterFlags) {
        self.label = label
        self.type = type
        self.flags = flags
    }

    public func getLabel() -> String? { label }
    public func getType() -> BuiltType { type }
    public func getFlags() -> ParameterFlags { flags }

    public mutating func setLabel(_ label: String?) { self.label = label }
    public mutating func setType(_ type: BuiltType) { self.type = type }
    public mutating func setVariadic() { flags = flags.withVariadic(true) }
    public mutating func setAutoClosure() { flags = flags.withAutoClosure(true) }
    public mutating func setOwnership(_ ownership: ParameterOwnership) {
        flags = flags.withOwnership(ownership)
    }
    public mutating func setNoDerivative() { flags = flags.withNoDerivative(true) }
    public mutating func setIsolated() { flags = flags.withIsolated(true) }
    public mutating func setSending() { flags = flags.withSending(true) }
    public mutating func setFlags(_ flags: ParameterFlags) { self.flags = flags }

    public func withLabel(_ label: String?) -> FunctionParam {
        return FunctionParam(label: label, type: type, flags: flags)
    }

    public func withType(_ type: BuiltType) -> FunctionParam {
        return FunctionParam(label: label, type: type, flags: flags)
    }

    public func withFlags(_ flags: ParameterFlags) -> FunctionParam {
        return FunctionParam(label: label, type: type, flags: flags)
    }
}

/// Parameter flags
public struct ParameterFlags: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32 = 0) {
        self.rawValue = rawValue
    }

    // Flag bits
    private static let variadicBit: UInt32 = 1 << 0
    private static let autoClosureBit: UInt32 = 1 << 1
    private static let noDerivativeBit: UInt32 = 1 << 2
    private static let isolatedBit: UInt32 = 1 << 3
    private static let sendingBit: UInt32 = 1 << 4
    private static let ownershipMask: UInt32 = 0x7 << 5

    // Ownership values in bits 5-7
    private static let ownershipDefault: UInt32 = 0 << 5
    private static let ownershipInOut: UInt32 = 1 << 5
    private static let ownershipShared: UInt32 = 2 << 5
    private static let ownershipOwned: UInt32 = 3 << 5

    public var isVariadic: Bool { (rawValue & Self.variadicBit) != 0 }
    public var isAutoClosure: Bool { (rawValue & Self.autoClosureBit) != 0 }
    public var isNoDerivative: Bool { (rawValue & Self.noDerivativeBit) != 0 }
    public var isIsolated: Bool { (rawValue & Self.isolatedBit) != 0 }
    public var isSending: Bool { (rawValue & Self.sendingBit) != 0 }

    public var ownership: ParameterOwnership {
        switch rawValue & Self.ownershipMask {
        case Self.ownershipInOut: return .inout
        case Self.ownershipShared: return .shared
        case Self.ownershipOwned: return .owned
        default: return .default
        }
    }

    public func withVariadic(_ value: Bool) -> ParameterFlags {
        if value {
            return ParameterFlags(rawValue: rawValue | Self.variadicBit)
        } else {
            return ParameterFlags(rawValue: rawValue & ~Self.variadicBit)
        }
    }

    public func withAutoClosure(_ value: Bool) -> ParameterFlags {
        if value {
            return ParameterFlags(rawValue: rawValue | Self.autoClosureBit)
        } else {
            return ParameterFlags(rawValue: rawValue & ~Self.autoClosureBit)
        }
    }

    public func withOwnership(_ ownership: ParameterOwnership) -> ParameterFlags {
        let cleared = rawValue & ~Self.ownershipMask
        let ownershipBits: UInt32
        switch ownership {
        case .default: ownershipBits = Self.ownershipDefault
        case .inout: ownershipBits = Self.ownershipInOut
        case .shared: ownershipBits = Self.ownershipShared
        case .owned: ownershipBits = Self.ownershipOwned
        }
        return ParameterFlags(rawValue: cleared | ownershipBits)
    }

    public func withNoDerivative(_ value: Bool) -> ParameterFlags {
        if value {
            return ParameterFlags(rawValue: rawValue | Self.noDerivativeBit)
        } else {
            return ParameterFlags(rawValue: rawValue & ~Self.noDerivativeBit)
        }
    }

    public func withIsolated(_ value: Bool) -> ParameterFlags {
        if value {
            return ParameterFlags(rawValue: rawValue | Self.isolatedBit)
        } else {
            return ParameterFlags(rawValue: rawValue & ~Self.isolatedBit)
        }
    }

    public func withSending(_ value: Bool) -> ParameterFlags {
        if value {
            return ParameterFlags(rawValue: rawValue | Self.sendingBit)
        } else {
            return ParameterFlags(rawValue: rawValue & ~Self.sendingBit)
        }
    }
}

/// Describe a lowered function parameter, parameterized on the type representation.
public struct ImplFunctionParam<BuiltType> {
    public let type: BuiltType
    public let convention: ImplParameterConvention
    public let options: ImplParameterInfoOptions

    public typealias ConventionType = ImplParameterConvention
    public typealias OptionsType = ImplParameterInfoOptions

    public init(type: BuiltType, convention: ImplParameterConvention, options: ImplParameterInfoOptions = []) {
        self.type = type
        self.convention = convention
        self.options = options
    }

    public func getConvention() -> ImplParameterConvention { convention }
    public func getOptions() -> ImplParameterInfoOptions { options }
    public func getType() -> BuiltType { type }

    public static func getConventionFromString(_ conventionString: String) -> ImplParameterConvention? {
        return ImplParameterConvention(string: conventionString)
    }

    public static func getDifferentiabilityFromString(_ string: String) -> ImplParameterInfoOptions? {
        if string.isEmpty {
            return ImplParameterInfoOptions()
        }
        if string == "@noDerivative" {
            return .notDifferentiable
        }
        return nil
    }

    public static func getSending() -> ImplParameterInfoOptions {
        return .sending
    }

    public static func getIsolated() -> ImplParameterInfoOptions {
        return .isolated
    }

    public static func getImplicitLeading() -> ImplParameterInfoOptions {
        return .implicitLeading
    }
}

public typealias ImplFunctionYield<Type> = ImplFunctionParam<Type>

/// Describe a lowered function result, parameterized on the type representation.
public struct ImplFunctionResult<BuiltType> {
    public let type: BuiltType
    public let convention: ImplResultConvention
    public let options: ImplResultInfoOptions

    public typealias ConventionType = ImplResultConvention
    public typealias OptionsType = ImplResultInfoOptions

    public init(type: BuiltType, convention: ImplResultConvention, options: ImplResultInfoOptions = []) {
        self.type = type
        self.convention = convention
        self.options = options
    }

    public func getConvention() -> ImplResultConvention { convention }
    public func getOptions() -> ImplResultInfoOptions { options }
    public func getType() -> BuiltType { type }

    public static func getConventionFromString(_ conventionString: String) -> ImplResultConvention? {
        return ImplResultConvention(string: conventionString)
    }

    public static func getDifferentiabilityFromString(_ string: String) -> ImplResultInfoOptions? {
        if string.isEmpty {
            return ImplResultInfoOptions()
        }
        if string == "@noDerivative" {
            return .notDifferentiable
        }
        return nil
    }

    public static func getSending() -> ImplResultInfoOptions {
        return .isSending
    }
}

/// Function type flags
public struct FunctionTypeFlags: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32 = 0) {
        self.rawValue = rawValue
    }

    // Convention bits (0-2)
    private static let conventionMask: UInt32 = 0x7
    private static let conventionSwift: UInt32 = 0
    private static let conventionBlock: UInt32 = 1
    private static let conventionThin: UInt32 = 2
    private static let conventionCFunctionPointer: UInt32 = 3

    // Flag bits
    private static let sendableBit: UInt32 = 1 << 3
    private static let asyncBit: UInt32 = 1 << 4
    private static let throwsBit: UInt32 = 1 << 5
    private static let differentiableBit: UInt32 = 1 << 6
    private static let escapingBit: UInt32 = 1 << 7
    private static let parameterFlagsBit: UInt32 = 1 << 8
    private static let extendedFlagsBit: UInt32 = 1 << 9

    // Number of parameters encoded in bits 16-31
    private static let numParametersShift: UInt32 = 16
    private static let numParametersMask: UInt32 = 0xFFFF0000

    public var convention: FunctionMetadataConvention {
        switch rawValue & Self.conventionMask {
        case Self.conventionBlock: return .block
        case Self.conventionThin: return .thin
        case Self.conventionCFunctionPointer: return .cFunctionPointer
        default: return .swift
        }
    }

    public var isSendable: Bool { (rawValue & Self.sendableBit) != 0 }
    public var isAsync: Bool { (rawValue & Self.asyncBit) != 0 }
    public var `throws`: Bool { (rawValue & Self.throwsBit) != 0 }
    public var isDifferentiable: Bool { (rawValue & Self.differentiableBit) != 0 }
    public var isEscaping: Bool { (rawValue & Self.escapingBit) != 0 }
    public var hasParameterFlags: Bool { (rawValue & Self.parameterFlagsBit) != 0 }
    public var hasExtendedFlags: Bool { (rawValue & Self.extendedFlagsBit) != 0 }

    public var numParameters: Int {
        return Int((rawValue & Self.numParametersMask) >> Self.numParametersShift)
    }

    public func withConvention(_ convention: FunctionMetadataConvention) -> FunctionTypeFlags {
        let cleared = rawValue & ~Self.conventionMask
        let conventionBits: UInt32
        switch convention {
        case .swift: conventionBits = Self.conventionSwift
        case .block: conventionBits = Self.conventionBlock
        case .thin: conventionBits = Self.conventionThin
        case .cFunctionPointer: conventionBits = Self.conventionCFunctionPointer
        }
        return FunctionTypeFlags(rawValue: cleared | conventionBits)
    }

    public func withSendable(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.sendableBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.sendableBit)
        }
    }

    public func withAsync(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.asyncBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.asyncBit)
        }
    }

    public func withThrows(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.throwsBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.throwsBit)
        }
    }

    public func withDifferentiable(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.differentiableBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.differentiableBit)
        }
    }

    public func withEscaping(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.escapingBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.escapingBit)
        }
    }

    public func withParameterFlags(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.parameterFlagsBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.parameterFlagsBit)
        }
    }

    public func withExtendedFlags(_ value: Bool) -> FunctionTypeFlags {
        if value {
            return FunctionTypeFlags(rawValue: rawValue | Self.extendedFlagsBit)
        } else {
            return FunctionTypeFlags(rawValue: rawValue & ~Self.extendedFlagsBit)
        }
    }

    public func withNumParameters(_ count: Int) -> FunctionTypeFlags {
        let cleared = rawValue & ~Self.numParametersMask
        let countBits = (UInt32(count) << Self.numParametersShift) & Self.numParametersMask
        return FunctionTypeFlags(rawValue: cleared | countBits)
    }
}

/// Implementation function type flags
public struct ImplFunctionTypeFlags {
    private var rep: UInt8 = 0
    private var pseudogeneric: Bool = false
    private var escaping: Bool = false
    private var concurrent: Bool = false
    private var async: Bool = false
    private var erasedIsolation: Bool = false
    private var differentiabilityKind: UInt8 = 0
    private var sendingResult: Bool = false

    public init() {}

    public init(
        rep: ImplFunctionRepresentation,
        pseudogeneric: Bool,
        noescape: Bool,
        concurrent: Bool,
        async: Bool,
        erasedIsolation: Bool,
        diffKind: ImplFunctionDifferentiabilityKind,
        hasSendingResult: Bool
    ) {
        self.rep = repToUInt8(rep)
        self.pseudogeneric = pseudogeneric
        self.escaping = noescape
        self.concurrent = concurrent
        self.async = async
        self.erasedIsolation = erasedIsolation
        self.differentiabilityKind = diffKindToUInt8(diffKind)
        self.sendingResult = hasSendingResult
    }

    private func repToUInt8(_ rep: ImplFunctionRepresentation) -> UInt8 {
        switch rep {
        case .thick: return 0
        case .block: return 1
        case .thin: return 2
        case .cFunctionPointer: return 3
        case .method: return 4
        case .objCMethod: return 5
        case .witnessMethod: return 6
        case .closure: return 7
        }
    }

    private func uint8ToRep(_ value: UInt8) -> ImplFunctionRepresentation {
        switch value {
        case 1: return .block
        case 2: return .thin
        case 3: return .cFunctionPointer
        case 4: return .method
        case 5: return .objCMethod
        case 6: return .witnessMethod
        case 7: return .closure
        default: return .thick
        }
    }

    private func diffKindToUInt8(_ kind: ImplFunctionDifferentiabilityKind) -> UInt8 {
        switch kind {
        case .nonDifferentiable: return 0
        case .forward: return 1
        case .reverse: return 2
        case .normal: return 3
        case .linear: return 4
        }
    }

    private func uint8ToDiffKind(_ value: UInt8) -> ImplFunctionDifferentiabilityKind {
        switch value {
        case 1: return .forward
        case 2: return .reverse
        case 3: return .normal
        case 4: return .linear
        default: return .nonDifferentiable
        }
    }

    public func getRepresentation() -> ImplFunctionRepresentation {
        return uint8ToRep(rep)
    }

    public func getDifferentiabilityKind() -> ImplFunctionDifferentiabilityKind {
        return uint8ToDiffKind(differentiabilityKind)
    }

    public func isAsync() -> Bool { async }
    public func isEscaping() -> Bool { escaping }
    public func isSendable() -> Bool { concurrent }
    public func isPseudogeneric() -> Bool { pseudogeneric }
    public func hasErasedIsolation() -> Bool { erasedIsolation }
    public func hasSendingResult() -> Bool { sendingResult }
    public func isDifferentiable() -> Bool {
        return getDifferentiabilityKind() != .nonDifferentiable
    }

    public func withRepresentation(_ newRep: ImplFunctionRepresentation) -> ImplFunctionTypeFlags {
        var copy = self
        copy.rep = repToUInt8(newRep)
        return copy
    }

    public func withSendable() -> ImplFunctionTypeFlags {
        var copy = self
        copy.concurrent = true
        return copy
    }

    public func withAsync() -> ImplFunctionTypeFlags {
        var copy = self
        copy.async = true
        return copy
    }

    public func withEscaping() -> ImplFunctionTypeFlags {
        var copy = self
        copy.escaping = true
        return copy
    }

    public func withErasedIsolation() -> ImplFunctionTypeFlags {
        var copy = self
        copy.erasedIsolation = true
        return copy
    }

    public func withPseudogeneric() -> ImplFunctionTypeFlags {
        var copy = self
        copy.pseudogeneric = true
        return copy
    }

    public func withDifferentiabilityKind(_ kind: ImplFunctionDifferentiabilityKind) -> ImplFunctionTypeFlags {
        var copy = self
        copy.differentiabilityKind = diffKindToUInt8(kind)
        return copy
    }

    public func withSendingResult() -> ImplFunctionTypeFlags {
        var copy = self
        copy.sendingResult = true
        return copy
    }
}
