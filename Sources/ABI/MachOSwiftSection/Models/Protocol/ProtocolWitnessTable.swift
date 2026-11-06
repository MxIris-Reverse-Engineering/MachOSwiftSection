import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ProtocolWitnessTable {
    public struct Layout: LayoutProtocol {
        public let descriptor: Pointer<ProtocolConformanceDescriptor>
    }
}
