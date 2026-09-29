import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ProtocolWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let descriptor: Pointer<ProtocolConformanceDescriptor>
    }
}
