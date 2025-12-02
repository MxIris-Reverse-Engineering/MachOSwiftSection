import Foundation
import MachOFoundation

public struct ValueWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let initializeBufferWithCopyOfBuffer: StoredPointer
        public let destroy: StoredPointer
        public let initializeWithCopy: StoredPointer
        public let assignWithCopy: StoredPointer
        public let initializeWithTake: StoredPointer
        public let assignWithTake: StoredPointer
        public let getEnumTagSinglePayload: StoredPointer
        public let storeEnumTagSinglePayload: StoredPointer

        public let size: StoredSize
        public let stride: StoredSize
        public let flags: ValueWitnessFlags
        public let numExtraInhabitants: UInt32
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public var typeLayout: TypeLayout {
        .init(size: layout.size, stride: layout.stride, flags: layout.flags, extraInhabitantCount: layout.numExtraInhabitants)
    }
}

public struct TypeLayout {
    public let size: StoredSize
    public let stride: StoredSize
    public let flags: ValueWitnessFlags
    public let extraInhabitantCount: UInt32
}
