import Foundation
import MachOKit
import MachOFoundation

public struct GenericBoxHeapMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let offset: UInt32
        public let boxedType: ConstMetadataPointer<Metadata>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
