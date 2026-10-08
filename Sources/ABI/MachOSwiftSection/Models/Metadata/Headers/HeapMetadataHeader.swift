import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct HeapMetadataHeader: HeapMetadataHeaderProtocol {
    public struct Layout: HeapMetadataHeaderLayout {
        public let layoutString: Pointer<String?>
        public let destroy: RawPointer
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }
}
