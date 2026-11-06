import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct MethodDefaultOverrideTableHeader {
    public struct Layout: LayoutProtocol {
        public let numEntries: UInt32
    }
}
