public struct ProtocolRequirementFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isInstance = ProtocolRequirementFlags(rawValue: 0x10)
    public static let maybeAsync = ProtocolRequirementFlags(rawValue: 0x20)

    public var kind: ProtocolRequirementKind {
        return ProtocolRequirementKind(rawValue: UInt8(rawValue & 0x0F))!
    }

    public var isCoroutine: Bool {
        switch kind {
        case .baseProtocol,
             .method,
             .`init`,
             .getter,
             .setter,
             .associatedTypeAccessFunction,
             .associatedConformanceAccessFunction:
            return false
        case .readCoroutine,
             .modifyCoroutine:
            return true
        }
    }

    public var isAsync: Bool {
        return !isCoroutine && contains(.maybeAsync)
    }
}
