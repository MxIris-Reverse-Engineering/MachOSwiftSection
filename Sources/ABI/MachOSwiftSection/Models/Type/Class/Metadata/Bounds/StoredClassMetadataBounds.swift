import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct StoredClassMetadataBounds {
    public struct Layout: LayoutProtocol {
        public let immediateMembersOffset: StoredPointerDifference
        public let bounds: MetadataBounds
    }
}
