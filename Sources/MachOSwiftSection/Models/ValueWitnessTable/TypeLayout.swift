import Foundation
import MachOFoundation

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
