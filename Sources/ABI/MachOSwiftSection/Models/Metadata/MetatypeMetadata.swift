import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct MetatypeMetadata: MetadataProtocol {
    public struct Layout: MetatypeMetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
    }
}
