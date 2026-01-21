import Foundation
import MachOFoundation

public struct MetatypeMetadata: MetadataProtocol {
    public struct Layout: MetatypeMetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
