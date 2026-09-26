import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ObjCClassWrapperMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let `class`: ConstMetadataPointer<ClassMetadataObjCInterop>
    }
}
