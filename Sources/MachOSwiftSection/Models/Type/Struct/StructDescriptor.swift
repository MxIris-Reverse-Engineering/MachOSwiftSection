import Foundation
import MachOKit

public struct StructDescriptor: LocatableLayoutWrapper, TypeContextDescriptorProtocol {
    public struct Layout: StructDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer<ContextDescriptorWrapper?>
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let numFields: UInt32
        public let fieldOffsetVector: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
