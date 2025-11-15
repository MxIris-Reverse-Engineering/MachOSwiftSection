import Foundation

public struct ClassMetadataBounds: ClassMetadataBoundsProtocol {
    public struct Layout: ClassMetadataBoundsLayout {
        public let negativeSizeInWords: UInt32
        public let positiveSizeInWords: UInt32
        public let immediateMembersOffset: StoredPointerDifference

        public init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32) {
            self.negativeSizeInWords = negativeSizeInWords
            self.positiveSizeInWords = positiveSizeInWords
            self.immediateMembersOffset = 0
        }

        public init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32, immediateMembersOffset: StoredPointerDifference) {
            self.negativeSizeInWords = negativeSizeInWords
            self.positiveSizeInWords = positiveSizeInWords
            self.immediateMembersOffset = immediateMembersOffset
        }
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
