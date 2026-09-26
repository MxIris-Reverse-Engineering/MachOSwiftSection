import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct AnyClassMetadata: AnyClassMetadataProtocol {
    public struct Layout: AnyClassMetadataLayout {
        public let kind: StoredPointer
        public let superclass: Pointer<AnyClassMetadata?>
    }
}
