import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
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
}
