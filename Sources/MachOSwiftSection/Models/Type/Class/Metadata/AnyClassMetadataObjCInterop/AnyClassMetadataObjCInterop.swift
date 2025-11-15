import Foundation
import MachOKit
import MachOFoundation

public struct AnyClassMetadataObjCInterop: AnyClassMetadataObjCInteropProtocol {
    public struct Layout: AnyClassMetadataObjCInteropLayout {
        public let kind: StoredPointer
        public let superclass: Pointer<AnyClassMetadataObjCInterop?>
        public let cache: RawPointer
        public let vtable: RawPointer
        public let data: StoredSize
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
