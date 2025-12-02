import Foundation
import MachOKit
import MachOFoundation

public struct FunctionTypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let flags: FunctionTypeFlags<StoredSize>
        public let resultType: ConstMetadataPointer<Metadata>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
