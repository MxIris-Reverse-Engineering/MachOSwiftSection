import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct StructMetadata: StructMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ValueTypeDescriptorWrapper>
    }

    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}
