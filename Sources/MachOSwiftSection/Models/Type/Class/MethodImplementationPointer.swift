import Foundation

public enum MethodImplementationPointer {
    case implementation(RelativeDirectRawPointer)
    case asyncImplementation(RelativeDirectRawPointer)
    case coroutineImplementation(RelativeDirectRawPointer)
}
