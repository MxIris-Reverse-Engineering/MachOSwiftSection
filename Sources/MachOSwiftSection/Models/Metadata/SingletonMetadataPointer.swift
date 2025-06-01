public struct SingletonMetadataPointer: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        let metadata: RelativeDirectPointer<Metadata>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
