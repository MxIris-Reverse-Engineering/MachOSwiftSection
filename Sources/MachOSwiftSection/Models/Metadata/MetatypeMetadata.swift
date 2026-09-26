import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct MetatypeMetadata: MetadataProtocol {
    public struct Layout: MetatypeMetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
    }
}
