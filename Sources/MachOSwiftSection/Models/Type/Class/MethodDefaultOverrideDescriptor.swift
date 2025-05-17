import Foundation

public struct MethodDefaultOverrideDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
