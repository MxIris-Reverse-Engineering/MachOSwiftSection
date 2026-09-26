import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct OverrideTableHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let numEntries: UInt32
    }
}
