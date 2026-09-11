import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct MethodDefaultOverrideTableHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let numEntries: UInt32
    }
}
