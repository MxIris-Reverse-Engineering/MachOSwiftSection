import Foundation
import MachOKit
import MachOFoundation


public struct HeapMetadataHeaderPrefix: HeapMetadataHeaderPrefixProtocol {
    public struct Layout: HeapMetadataHeaderPrefixLayout {
        public let destroy: RawPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
