public struct CanonicalSpecializedMetadatasCachingOnceToken: LocatableLayoutWrapper {
    public struct Layout {
        let token: RelativeDirectPointer<SwiftOnceToken>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
