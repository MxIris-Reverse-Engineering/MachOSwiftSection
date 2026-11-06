import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct CanonicalSpecializedMetadatasListEntry {
    public struct Layout: LayoutProtocol {
        let metadata: RelativeDirectPointer<MetadataWrapper>
    }
}
