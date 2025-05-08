import Foundation

public struct EnumDescriptor: LocatableLayoutWrapper, TypeContextDescriptorProtocol {
    public struct Layout: EnumDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeIndirectablePointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>
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
