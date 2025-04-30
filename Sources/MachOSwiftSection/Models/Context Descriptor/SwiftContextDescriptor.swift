import Foundation
@_spi(Support) import MachOKit

public struct SwiftContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: SwiftContextDescriptorFlags
        public let parent: RelativeIndirectPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
