import Foundation

public struct MetadataBounds: MetadataBoundsProtocol {
    public struct Layout: MetadataBoundsLayout {
        public let negativeSizeInWords: UInt32
        public let positiveSizeInWords: UInt32
        public init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32) {
            self.negativeSizeInWords = negativeSizeInWords
            self.positiveSizeInWords = positiveSizeInWords
        }
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
