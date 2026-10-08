import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct AnyClassMetadataObjCInterop: AnyClassMetadataObjCInteropProtocol {
    public struct Layout: AnyClassMetadataObjCInteropLayout {
        public let kind: StoredPointer
        public let superclass: Pointer<AnyClassMetadataObjCInterop?>
        public let cache: RawPointer
        public let vtable: RawPointer
        public let data: StoredSize
    }
}
