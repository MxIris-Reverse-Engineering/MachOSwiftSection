import Foundation

public enum ProtocolDescriptorWithObjCInterop {
    case objc(ObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
