import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct OverrideTableHeader {
    public struct Layout: LayoutProtocol {
        public let numEntries: UInt32
    }
}
