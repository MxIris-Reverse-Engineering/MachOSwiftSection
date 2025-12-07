import MachOKit
import MachOFoundation

public struct ValueMetadata: ValueMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<ValueTypeDescriptorWrapper>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
