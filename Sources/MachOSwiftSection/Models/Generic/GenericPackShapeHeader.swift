import MachOBase

@LocatableLayoutWrapping
public struct GenericPackShapeHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let numPacks: UInt16
        public let numShapeClasses: UInt16
    }
}
