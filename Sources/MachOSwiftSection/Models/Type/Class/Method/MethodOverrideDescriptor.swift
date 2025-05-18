import Foundation

public struct MethodOverrideDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let `class`: RelativeContextPointer<ContextDescriptorWrapper?>
        public let method: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
