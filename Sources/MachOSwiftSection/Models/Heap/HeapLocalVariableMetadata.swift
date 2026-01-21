import Foundation
import MachOKit
import MachOFoundation

public struct HeapLocalVariableMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let offsetToFirstCapture: UInt32
        public let captureDescription: Pointer<String?>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
