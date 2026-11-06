import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct CanonicalSpecializedMetadataAccessorsListEntry {
    public struct Layout: LayoutProtocol {
        public let accessor: RelativeDirectRawPointer
    }
}
