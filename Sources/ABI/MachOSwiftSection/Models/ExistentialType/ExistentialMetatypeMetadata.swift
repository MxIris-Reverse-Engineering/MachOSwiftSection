import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ExistentialMetatypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
        public let flags: ExistentialTypeFlags
    }
}
