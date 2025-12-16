import Foundation
import MachOFoundation
import SwiftStdlibToolbox

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
    /*@inlinable*/
    public var numberOfCases: Int {
        numberOfPayloadCases + numberOfEmptyCases
    }

    /*@inlinable*/
    public var numberOfEmptyCases: Int {
        layout.numEmptyCases.int
    }

    /*@inlinable*/
    public var numberOfPayloadCases: Int {
        (layout.numPayloadCasesAndPayloadSizeOffset & 0x00FF_FFFF).int
    }

    /*@inlinable*/
    public var hasPayloadSizeOffset: Bool {
        payloadSizeOffset != 0
    }

    /*@inlinable*/
    public var payloadSizeOffset: Int {
        .init((layout.numPayloadCasesAndPayloadSizeOffset & 0xFF00_0000) >> 24)
    }
}

extension EnumDescriptor {
    public var isSingleEmptyCaseOnly: Bool {
        numberOfCases == 1 && numberOfEmptyCases == 1 && numberOfPayloadCases == 0
    }
    
    public var isSinglePayloadCaseOnly: Bool {
        numberOfCases == 1 && numberOfEmptyCases == 0 && numberOfPayloadCases == 1
    }
    
    public var isSinglePayload: Bool {
        numberOfCases > 1 && numberOfEmptyCases > 0 && numberOfPayloadCases == 1
    }
    
    public var isMultiPayload: Bool {
        numberOfCases > 1 && numberOfPayloadCases > 1
    }
}
