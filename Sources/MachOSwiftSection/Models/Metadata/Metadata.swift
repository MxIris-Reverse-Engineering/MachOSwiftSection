import Foundation

public struct Metadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        /// The kind. Only valid for non-class metadata; getKind() must be used to get
        /// the kind value.
        public let kind: StoredPointer
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

