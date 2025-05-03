import Foundation

public struct ProtocolRequirement: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: ProtocolRequirementFlags
        public let defaultImplementation: RelativeOffset
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

public struct ProtocolRequirementFlags: OptionSet {
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
        case .baseProtocol, .method, .`init`, .getter, .setter, .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
            return false
        case .readCoroutine, .modifyCoroutine:
            return true
        }
    }
    
    public var isAsync: Bool {
        return !isCoroutine && contains(.maybeAsync)
    }
}

public enum ProtocolRequirementKind: UInt8 {
    case baseProtocol
    case method
    case `init`
    case getter
    case setter
    case readCoroutine
    case modifyCoroutine
    case associatedTypeAccessFunction
    case associatedConformanceAccessFunction
}
