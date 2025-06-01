import Foundation
import MachOKit
import MachOFoundation

public struct ModuleContextDescriptor: ModuleContextDescriptorProtocol {
    public struct Layout: ModuleContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }

    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}









