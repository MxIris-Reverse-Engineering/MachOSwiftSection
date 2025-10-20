import Foundation
import MachOFoundation

public struct ValueWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let size: StoredSize
        public let stride: StoredSize
        public let flags: ValueWitnessFlags
        public let numExtraInhabitants: UInt32
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
