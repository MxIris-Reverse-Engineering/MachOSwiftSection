import Foundation

@LocatableLayoutWrapping
public struct Metadata: MetadataProtocol, Hashable {
    public typealias HeaderType = TypeMetadataHeader

    public struct Layout: MetadataLayout, Hashable {
        /// The kind. Only valid for non-class metadata
        public let kind: StoredPointer
    }
}
