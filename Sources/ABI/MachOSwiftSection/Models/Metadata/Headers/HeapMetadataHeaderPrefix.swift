import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct HeapMetadataHeaderPrefix: HeapMetadataHeaderPrefixProtocol {
    public struct Layout: HeapMetadataHeaderPrefixLayout {
        public let destroy: RawPointer
    }
}
