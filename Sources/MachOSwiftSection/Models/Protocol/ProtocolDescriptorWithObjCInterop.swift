import Foundation
import MachOFoundation

public enum ProtocolDescriptorWithObjCInterop: Resolvable {
    case objc(ObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
