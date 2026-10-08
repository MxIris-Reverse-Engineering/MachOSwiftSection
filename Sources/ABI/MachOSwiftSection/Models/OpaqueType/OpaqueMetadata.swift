import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct OpaqueMetadata: MetadataProtocol {
    public typealias HeaderType = TypeMetadataHeaderBase

    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
    }
}
