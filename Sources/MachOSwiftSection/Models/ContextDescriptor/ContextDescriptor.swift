import Foundation
import MachOKit
import MachOFoundation

public struct ContextDescriptor: ContextDescriptorProtocol {
    public struct Layout: ContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

