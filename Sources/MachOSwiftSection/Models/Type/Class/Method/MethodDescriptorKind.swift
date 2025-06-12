import Foundation

public enum MethodDescriptorKind: UInt8, CaseIterable, CustomStringConvertible {
    case method
    case `init`
    case getter
    case setter
    case modifyCoroutine
    case readCoroutine
    
    public var description: String {
        switch self {
        case .method:
            return "Method"
        case .`init`:
            return " Init "
        case .getter:
            return "Getter"
        case .setter:
            return "Setter"
        case .modifyCoroutine:
            return "Modify"
        case .readCoroutine:
            return " Read "
        }
    }
}
