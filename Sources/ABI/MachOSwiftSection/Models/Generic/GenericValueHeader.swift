import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericValueHeader {
    public struct Layout: LayoutProtocol {
        public let numValues: UInt32
    }
}
