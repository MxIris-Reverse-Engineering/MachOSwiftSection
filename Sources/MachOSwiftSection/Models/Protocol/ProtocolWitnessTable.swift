import Foundation
import MachOFoundation

public struct ProtocolWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let descriptor: Pointer<ProtocolConformanceDescriptor>
    }

    public var layout: Layout

    public var offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
