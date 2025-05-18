import Foundation

public struct ObjCResilientClassStubInfo: LocatableLayoutWrapper {
    public struct Layout {
        public let stub: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
