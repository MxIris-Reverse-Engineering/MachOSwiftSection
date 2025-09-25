import Foundation
import MachOFoundation

public struct VTableDescriptorHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let vTableOffset: UInt32
        public let vTableSize: UInt32
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
