import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct GenericValueHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let numValues: UInt32
    }
}
