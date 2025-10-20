import Foundation
import MachOFoundation

public enum ProtocolDescriptorWithObjCInterop: Resolvable, Equatable {
    case objc(ObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
