import Foundation
@_spi(Support) import MachOKit

public struct ModuleContextDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let name: RelativeOffset
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }

    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension ModuleContextDescriptor {
    public func name(in machO: MachOFile) -> String? {
        let offset = offset(of: \.name) + Int(layout.name)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }
}
