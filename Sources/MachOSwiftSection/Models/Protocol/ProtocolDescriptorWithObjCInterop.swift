import Foundation
import FoundationToolbox
import MachOFoundation

@AssociatedValue(.public)
@CaseCheckable(.public)
public enum ProtocolDescriptorWithObjCInterop: Resolvable, Equatable {
    case objc(ObjCProtocolPrefix)
    case swift(ProtocolDescriptor)
}
