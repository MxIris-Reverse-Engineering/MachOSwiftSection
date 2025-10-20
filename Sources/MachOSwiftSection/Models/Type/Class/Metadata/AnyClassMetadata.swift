import Foundation
import MachOFoundation

public struct AnyClassMetadata: HeapMetadataProtocol {
    public struct Layout: AnyClassMetadataLayout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
