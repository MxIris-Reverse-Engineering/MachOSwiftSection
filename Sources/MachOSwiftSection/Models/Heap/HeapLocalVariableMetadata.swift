import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct HeapLocalVariableMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let offsetToFirstCapture: UInt32
        public let captureDescription: Pointer<CaptureDescriptor?>
    }
}
