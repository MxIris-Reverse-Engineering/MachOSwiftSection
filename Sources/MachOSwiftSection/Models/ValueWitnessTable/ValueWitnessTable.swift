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

@dynamicMemberLookup
public struct TypeLayout {
    public let size: StoredSize
    public let stride: StoredSize
    public let flags: ValueWitnessFlags
    public let extraInhabitantCount: UInt32
    
    public subscript<Value>(dynamicMember keyPath: KeyPath<ValueWitnessFlags, Value>) -> Value {
        flags[keyPath: keyPath]
    }
}

extension TypeLayout: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "TypeLayout(size: \(size), stride: \(stride), alignment: \(flags.alignment), extraInhabitantCount: \(extraInhabitantCount))"
    }
    
    public var debugDescription: String {
        "\(description.dropLast(1)), isPOD: \(flags.isPOD), isInlineStorage: \(flags.isInlineStorage), isBitwiseTakable: \(flags.isBitwiseTakable), isBitwiseBorrowable: \(flags.isBitwiseBorrowable), isCopyable: \(flags.isCopyable), hasEnumWitnesses: \(flags.hasEnumWitnesses), isIncomplete: \(flags.isIncomplete))"
    }
}
