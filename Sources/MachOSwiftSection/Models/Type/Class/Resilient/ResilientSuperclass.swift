import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ResilientSuperclass: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let superclass: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}


