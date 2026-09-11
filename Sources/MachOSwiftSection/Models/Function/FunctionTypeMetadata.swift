import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct FunctionTypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let flags: FunctionTypeFlags<StoredSize>
        public let resultType: ConstMetadataPointer<Metadata>
    }
}
