import Foundation
import MachOFoundation

public struct EnumMetadata: EnumMetadataProtocol {
    public struct Layout: EnumMetadataLayout {
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
