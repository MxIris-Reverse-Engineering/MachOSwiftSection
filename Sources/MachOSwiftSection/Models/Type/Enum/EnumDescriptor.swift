import Foundation
import MachOFoundation

public struct EnumDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: EnumDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let numPayloadCasesAndPayloadSizeOffset: UInt32
        public let numEmptyCases: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
