import Foundation
import MachOKit
import MachOMacro

public struct ResilientSuperclass: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        public let superclass: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}


