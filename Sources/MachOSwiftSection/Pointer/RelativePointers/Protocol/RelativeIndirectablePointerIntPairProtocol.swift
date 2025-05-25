import Foundation
import MachOKit

public protocol RelativeIndirectablePointerIntPairProtocol: RelativeIndirectablePointerProtocol {
    typealias Integer = Value.RawValue
    associatedtype Value: RawRepresentable where Value.RawValue: FixedWidthInteger
    var relativeOffsetPlusIndirectAndInt: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativeIndirectablePointerIntPairProtocol {
    public var relativeOffsetPlusIndirect: Offset {
        relativeOffsetPlusIndirectAndInt & ~mask
    }

    public var relativeOffset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast((relativeOffsetPlusIndirectAndInt & mask) >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}

extension RelativeIndirectablePointerIntPairProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}

extension RelativeIndirectablePointerIntPairProtocol where Pointee: OptionalProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOImage) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
