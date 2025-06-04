import Foundation
import MachOFoundation

public struct ObjCResilientClassStubInfo: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let stub: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
