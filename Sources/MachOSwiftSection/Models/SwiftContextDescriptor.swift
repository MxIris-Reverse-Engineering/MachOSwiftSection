import Foundation
@_spi(Support) import MachOKit

public struct SwiftContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: UInt32
        public let parent: Int32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension SwiftContextDescriptor {
    public var flags: SwiftContextDescriptorFlags {
        return SwiftContextDescriptorFlags(rawValue: layout.flags)
    }
}
