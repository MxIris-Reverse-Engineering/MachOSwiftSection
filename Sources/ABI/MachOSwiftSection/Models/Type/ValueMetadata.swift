import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ValueMetadata: ValueMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ValueTypeDescriptorWrapper>
    }
}
