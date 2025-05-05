import Foundation

public struct GenericWitnessTable: LayoutWrapperWithOffset {
    public struct Layout {
        public let witnessTableSizeinWords: UInt16
        public let witnessTablePrivateSizeInWordsAndRequiresInstantiation: UInt16
        public let instantiator: Int32
        public let privateData: Int32
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
