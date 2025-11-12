import Foundation
import MachOKit
import MachOFoundation

public struct HeapMetadataHeader: HeapMetadataHeaderProtocol {
    public struct Layout: HeapMetadataHeaderLayout {
        public let layoutString: Pointer<String?>
        public let destroy: RawPointer
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
