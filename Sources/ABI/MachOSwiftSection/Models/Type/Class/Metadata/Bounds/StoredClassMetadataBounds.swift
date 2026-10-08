import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct StoredClassMetadataBounds: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let immediateMembersOffset: StoredPointerDifference
        public let bounds: MetadataBounds
    }
}
