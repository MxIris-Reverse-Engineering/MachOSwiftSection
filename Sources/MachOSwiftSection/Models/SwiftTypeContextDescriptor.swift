import Foundation
@_spi(Support) import MachOKit

public struct SwiftTypeContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let context: SwiftContextDescriptor.Layout
        public let name: Int32
        public let accessFunctionPtr: Int32
        public let fieldDescriptor: Int32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
