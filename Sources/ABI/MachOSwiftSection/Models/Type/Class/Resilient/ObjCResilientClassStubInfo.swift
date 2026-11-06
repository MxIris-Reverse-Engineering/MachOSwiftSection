import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ObjCResilientClassStubInfo {
    public struct Layout: LayoutProtocol {
        public let stub: RelativeDirectRawPointer
    }
}
