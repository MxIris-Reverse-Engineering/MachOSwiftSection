import Foundation

@LocatableLayoutWrapping
public struct MetadataBounds: MetadataBoundsProtocol {
    public struct Layout: MetadataBoundsLayout {
        public let negativeSizeInWords: UInt32
        public let positiveSizeInWords: UInt32
        public init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32) {
            self.negativeSizeInWords = negativeSizeInWords
            self.positiveSizeInWords = positiveSizeInWords
        }
    }
}
