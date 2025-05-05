import Foundation

public struct EnumDescriptor: LayoutWrapperWithOffset, TypeContextDescriptorProtocol {
    public struct Layout: EnumDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let numPayloadCasesAndPayloadSizeOffset: UInt32
        public let numEmptyCases: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
