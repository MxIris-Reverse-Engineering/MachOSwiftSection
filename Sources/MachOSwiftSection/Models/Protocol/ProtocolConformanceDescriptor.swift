import Foundation
import MachOKit

public struct ProtocolConformanceDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let protocolDescriptor: RelativeIndirectablePointer<ProtocolDescriptor?>
        public let typeReference: TypeReference
        public let witnessTablePattern: RelativeDirectPointer<ProtocolWitnessTable>
        public let flags: ProtocolConformanceFlags
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ProtocolConformanceDescriptor {
    public func protocolDescriptor(in machO: MachOFile) throws -> ProtocolDescriptor? {
        try layout.protocolDescriptor.resolve(from: offset(of: \.protocolDescriptor).cast(), in: machO)
    }
}
    
