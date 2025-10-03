import Foundation
import MachOFoundation
import MachOKit

public struct FixedArrayTypeMetadata: MetadataProtocol {
    public struct Layout: FixedArrayTypeMetadataLayout {
        public let kind: StoredPointer
        public let count: StoredPointerDifference
        public let element: ConstMetadataPointer<Metadata>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
