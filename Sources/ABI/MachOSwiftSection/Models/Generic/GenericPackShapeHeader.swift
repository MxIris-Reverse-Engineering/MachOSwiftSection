import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericPackShapeHeader {
    public struct Layout: LayoutProtocol {
        public let numPacks: UInt16
        public let numShapeClasses: UInt16
    }
}
