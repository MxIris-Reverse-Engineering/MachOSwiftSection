import MachOBase

@ResolvableLocatableLayoutWrapper
public struct SingletonMetadataPointer {
    public struct Layout: LayoutProtocol {
        let metadata: RelativeDirectPointer<Metadata>
    }
}
