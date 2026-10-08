import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct CanonicalSpecializedMetadatasListEntry: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        let metadata: RelativeDirectPointer<MetadataWrapper>
    }
}
