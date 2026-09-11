import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct HeapMetadataHeaderPrefix: HeapMetadataHeaderPrefixProtocol {
    public struct Layout: HeapMetadataHeaderPrefixLayout {
        public let destroy: RawPointer
    }
}
