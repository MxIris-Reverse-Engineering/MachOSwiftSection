import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct TypeMetadataHeader: TypeMetadataHeaderProtocol {
    public struct Layout: TypeMetadataHeaderLayout {
        public let layoutString: Pointer<String?>
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
