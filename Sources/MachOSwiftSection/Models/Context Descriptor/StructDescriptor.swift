import Foundation
import MachOKit

public struct StructDescriptor: LayoutWrapperWithOffset, TypeContextDescriptorProtocol {
    public struct Layout: StructDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let numFields: UInt32
        public let fieldOffsetVector: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
