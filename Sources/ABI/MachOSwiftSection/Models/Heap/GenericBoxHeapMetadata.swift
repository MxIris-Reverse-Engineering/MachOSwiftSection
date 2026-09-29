import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct GenericBoxHeapMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let offset: UInt32
        public let boxedType: ConstMetadataPointer<Metadata>
    }
}
