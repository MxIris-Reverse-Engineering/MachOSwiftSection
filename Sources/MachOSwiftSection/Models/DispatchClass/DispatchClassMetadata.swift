import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct DispatchClassMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let opaque: RawPointer
        public let opaqueObjC1: RawPointer
        public let opaqueObjC2: RawPointer
        public let opaqueObjC3: RawPointer
        public let vTableType: UInt64
        public let vTableInvoke: RawPointer
    }
}
