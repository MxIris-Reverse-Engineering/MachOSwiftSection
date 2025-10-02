import Foundation
import MachOFoundation

public struct EnumDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: EnumDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeDirectPointer<MetadataAccessor>
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

extension EnumDescriptor {
    public var payloadSizeOffset: Int {
        .init((layout.numPayloadCasesAndPayloadSizeOffset & 0xFF00000) >> 24)
    }
    
    public var numberOfPayloadCases: UInt32 {
        layout.numPayloadCasesAndPayloadSizeOffset & 0x00FFFFFF
    }
}
