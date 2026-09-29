import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct VTableDescriptorHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let vTableOffset: UInt32
        public let vTableSize: UInt32
    }
}
