import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct CanonicalSpecializedMetadataAccessorsListEntry: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let accessor: RelativeDirectRawPointer
    }
}
