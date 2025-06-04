import Foundation

public struct OverrideTableHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let numEntries: UInt32
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
