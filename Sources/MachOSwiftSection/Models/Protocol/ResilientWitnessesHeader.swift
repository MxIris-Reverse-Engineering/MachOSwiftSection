import Foundation

public struct ResilientWitnessesHeader: LayoutWrapperWithOffset {
    public struct Layout {
        public let numWitnesses: UInt32
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
