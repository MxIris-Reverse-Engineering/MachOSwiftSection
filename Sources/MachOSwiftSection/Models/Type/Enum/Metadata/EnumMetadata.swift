import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct EnumMetadata: EnumMetadataProtocol {
    public struct Layout: EnumMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ValueTypeDescriptorWrapper>
    }
}
