import SwiftStdlibToolbox

@CaseCheckable(.public)
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

extension ProtocolRequirementKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .baseProtocol:
            "BaseProtocol"
        case .method:
            "Method"
        case .`init`:
            "Init"
        case .getter:
            "Getter"
        case .setter:
            "Setter"
        case .readCoroutine:
            "ReadCoroutine"
        case .modifyCoroutine:
            "ModifyCoroutine"
        case .associatedTypeAccessFunction:
            "AssociatedTypeAccessFunction"
        case .associatedConformanceAccessFunction:
            "AssociatedConformanceAccessFunction"
        }
    }
}
