import Foundation

public enum ProtocolDescriptorWithObjCInterop: Resolvable {
    case objc(RelativeObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
