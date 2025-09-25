import Foundation
import MachOFoundation

public struct GenericWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let witnessTableSizeInWords: UInt16
        public let witnessTablePrivateSizeInWordsAndRequiresInstantiation: UInt16
        public let instantiator: RelativeDirectRawPointer
        public let privateData: RelativeDirectRawPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
