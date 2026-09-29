import MachOBase

@LocatableLayoutWrapping
public struct SingletonMetadataPointer: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        let metadata: RelativeDirectPointer<Metadata>
    }
}
