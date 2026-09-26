import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ExtendedExistentialTypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let shape: Pointer<ExtendedExistentialTypeShape>
    }
}
