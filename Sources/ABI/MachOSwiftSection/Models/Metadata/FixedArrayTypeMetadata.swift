import Foundation
import MachOBase
import MachOKit

@LocatableLayoutWrapping
public struct FixedArrayTypeMetadata: MetadataProtocol {
    public struct Layout: FixedArrayTypeMetadataLayout {
        public let kind: StoredPointer
        public let count: StoredPointerDifference
        public let element: ConstMetadataPointer<Metadata>
    }
}
