import Foundation

public struct Metadata: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: UInt32
        public let typeDescriptor: UInt64
        public let typeMetadataAddress: UInt64
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
