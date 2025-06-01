import Foundation
import MachOFoundation

public enum MethodImplementationPointer {
    case implementation(RelativeDirectRawPointer)
    case asyncImplementation(RelativeDirectRawPointer)
    case coroutineImplementation(RelativeDirectRawPointer)
}
