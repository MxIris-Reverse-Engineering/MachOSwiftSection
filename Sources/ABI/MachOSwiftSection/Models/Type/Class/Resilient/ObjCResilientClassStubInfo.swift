import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ObjCResilientClassStubInfo: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let stub: RelativeDirectRawPointer
    }
}
