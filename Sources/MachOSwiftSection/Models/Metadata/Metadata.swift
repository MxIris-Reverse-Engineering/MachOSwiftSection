import Foundation

public struct Metadata: MetadataProtocol, Hashable {
    public typealias HeaderType = TypeMetadataHeader

    public struct Layout: MetadataLayout, Hashable {
        /// The kind. Only valid for non-class metadata
        public let kind: StoredPointer
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
