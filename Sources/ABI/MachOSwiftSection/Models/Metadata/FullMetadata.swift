import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct FullMetadata<Metadata: MetadataProtocol> {
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
}
