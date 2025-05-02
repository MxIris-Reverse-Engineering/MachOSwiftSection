import Foundation

public struct EnumDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let context: TypeContextDescriptor.Layout
        public let numPayloadCasesAndPayloadSizeOffset: UInt32
        public let numEmptyCases: UInt32
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
    
}
