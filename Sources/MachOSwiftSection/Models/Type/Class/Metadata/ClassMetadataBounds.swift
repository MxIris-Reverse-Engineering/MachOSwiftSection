import Foundation

public struct ClassMetadataBounds: ClassMetadataBoundsProtocol {
    public struct Layout: ClassMetadataBoundsLayout {
        public let negativeSizeInWords: UInt32
        public let positiveSizeInWords: UInt32
        public let immediateMembersOffset: StoredPointerDifference
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
