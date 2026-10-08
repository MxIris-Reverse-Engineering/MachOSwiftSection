import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ExistentialMetatypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
        public let flags: ExistentialTypeFlags
    }
}
