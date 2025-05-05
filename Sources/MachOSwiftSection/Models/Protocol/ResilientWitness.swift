import Foundation

public struct ResilientWitness: LayoutWrapperWithOffset {
    public struct Layout {
        public let requirement: RelativeIndirectablePointer<ProtocolRequirement>
        public let impl: RelativeDirectRawPointer
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
