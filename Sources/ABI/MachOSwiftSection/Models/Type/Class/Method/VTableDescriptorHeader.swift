import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct VTableDescriptorHeader {
    public struct Layout: LayoutProtocol {
        public let vTableOffset: UInt32
        public let vTableSize: UInt32
    }
}
