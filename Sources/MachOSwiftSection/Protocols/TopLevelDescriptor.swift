public protocol TopLevelDescriptor: ResolvableLocatableLayoutWrapper {
    var actualSize: Int { get }
}

extension TopLevelDescriptor {
    public var actualSize: Int {
        return layoutSize
    }
}
