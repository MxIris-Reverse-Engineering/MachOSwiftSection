import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ValueMetadata: ValueMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ValueTypeDescriptorWrapper>
    }
}
