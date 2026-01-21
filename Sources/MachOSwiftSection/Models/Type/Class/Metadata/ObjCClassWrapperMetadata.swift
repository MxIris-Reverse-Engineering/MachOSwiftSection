import Foundation
import MachOFoundation

public struct ObjCClassWrapperMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let `class`: ConstMetadataPointer<ClassMetadataObjCInterop>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
