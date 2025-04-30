import Foundation
@_spi(Support) import MachOKit

public struct SwiftModuleContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let context: SwiftContextDescriptor.Layout
        public let name: RelativeDirectPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}

extension SwiftModuleContextDescriptor {
    public func name(in machO: MachOFile) -> String? {
        let offset = offset(of: \.name) + Int(layout.name)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }
}
