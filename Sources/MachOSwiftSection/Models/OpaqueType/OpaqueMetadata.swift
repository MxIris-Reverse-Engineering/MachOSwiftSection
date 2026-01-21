import Foundation
import MachOKit
import MachOFoundation

public struct OpaqueMetadata: MetadataProtocol {
    public typealias HeaderType = TypeMetadataHeaderBase

    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
