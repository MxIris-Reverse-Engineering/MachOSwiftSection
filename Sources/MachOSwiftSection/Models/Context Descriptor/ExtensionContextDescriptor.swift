import Foundation
import MachOKit

public struct ExtensionContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let extendedContext: RelativeOffset
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
