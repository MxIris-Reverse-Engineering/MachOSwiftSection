import Foundation

public struct MethodDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

