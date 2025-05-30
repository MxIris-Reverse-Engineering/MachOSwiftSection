import Foundation

public enum ProtocolDescriptorWithObjCInterop: Resolvable {
    case objc(ObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
