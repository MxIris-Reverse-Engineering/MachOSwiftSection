import Foundation

public enum MethodDescriptorKind: UInt8 {
    case method
    case `init`
    case getter
    case setter
    case modifyCoroutine
    case readCoroutine
}
