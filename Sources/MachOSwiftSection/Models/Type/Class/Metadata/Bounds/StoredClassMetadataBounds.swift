import Foundation
import MachOKit
import MachOFoundation

public struct StoredClassMetadataBounds: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let immediateMembersOffset: StoredPointerDifference
        public let bounds: MetadataBounds
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
