import Foundation
import MachOKit

public struct OpaqueTypeDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
