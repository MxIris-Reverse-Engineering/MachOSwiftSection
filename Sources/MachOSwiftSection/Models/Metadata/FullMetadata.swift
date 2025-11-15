import Foundation
import MachOKit
import MachOFoundation

public struct FullMetadata<Metadata: MetadataProtocol>: ResolvableLocatableLayoutWrapper {
    @dynamicMemberLookup
    public struct Layout: LayoutProtocol {
        public let header: Metadata.HeaderType.Layout
        public let metadata: Metadata.Layout

        public subscript<T>(dynamicMember keyPath: KeyPath<Metadata.HeaderType.Layout, T>) -> T {
            header[keyPath: keyPath]
        }

        public subscript<T>(dynamicMember keyPath: KeyPath<Metadata.Layout, T>) -> T {
            metadata[keyPath: keyPath]
        }
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
