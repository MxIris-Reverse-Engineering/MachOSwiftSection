import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct HeapMetadataHeader: HeapMetadataHeaderProtocol {
    public struct Layout: HeapMetadataHeaderLayout {
        public let layoutString: Pointer<String?>
        public let destroy: RawPointer
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }
}
