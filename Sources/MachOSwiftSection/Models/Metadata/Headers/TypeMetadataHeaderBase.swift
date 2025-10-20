import Foundation
import MachOKit
import MachOFoundation


public struct TypeMetadataHeaderBase: TypeMetadataHeaderBaseProtocol {
    public struct Layout: TypeMetadataHeaderBaseLayout {
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
