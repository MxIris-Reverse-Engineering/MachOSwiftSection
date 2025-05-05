import Foundation
import MachOKit

public typealias RelativeOffset = Int32
public typealias RelativeDirectPointer<Pointee> = TargetRelativeDirectPointer<Pointee, RelativeOffset>
public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<Any, RelativeOffset>
public typealias RelativeIndirectPointer<Pointee> = TargetRelativeIndirectPointer<Pointee, RelativeOffset>
public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<Any, RelativeOffset>
public typealias RelativeIndirectablePointer<Pointee> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset>
public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<Any, RelativeOffset>
public typealias RelativeIndirectablePointerIntPair<Pointee, Integer: FixedWidthInteger> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer>
public typealias RelativeIndirectableRawPointerIntPair<Integer: FixedWidthInteger> = TargetRelativeIndirectablePointerIntPair<Any, RelativeOffset, Integer>

public protocol RelativePointerOptional: ExpressibleByNilLiteral {
    associatedtype Wrapped
    static func makeOptional(from wrappedValue: Wrapped) -> Self
}

extension Optional: RelativePointerOptional {
    public static func makeOptional(from wrappedValue: Wrapped) -> Self {
        return .some(wrappedValue)
    }
}

public protocol RelativePointer {
    associatedtype Pointee
    associatedtype Offset: FixedWidthInteger
    var relativeOffset: Offset { get }
    var isIndirect: Bool { get }
}

extension RelativePointer {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try machO.fileHandle.read(offset: numericCast(resolveFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try machO.fileHandle.read(offset: numericCast(resolveFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
    }

    public func resolveFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
        let resolvedDirectFileOffset = Int(fileOffset) + Int(relativeOffset)

        if isIndirect {
            let virtualAddress: UInt64 = try machO.fileHandle.read(offset: numericCast(resolvedDirectFileOffset + machO.headerStartOffset))
            let resolvedFileOffset: Int = machO.fileOffset(of: virtualAddress).cast()
            return resolvedFileOffset
        } else {
            return resolvedDirectFileOffset
        }
    }

    public var isDirect: Bool {
        return !isIndirect
    }

    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}

extension RelativePointer where Pointee: RelativePointerOptional {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        let result: Pointee.Wrapped = try machO.fileHandle.read(offset: numericCast(resolveFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
        return .makeOptional(from: result)
    }
}

extension RelativePointer where Pointee == String? {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee? {
        guard isValid else { return nil }
        return try machO.fileHandle.readString(offset: numericCast(resolveFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
    }
}

extension RelativePointer where Pointee == String {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try machO.fileHandle.readString(offset: numericCast(resolveFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset)) ?? ""
    }
}

extension RelativePointer where Pointee: LayoutWrapperWithOffset {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        let offset = try resolveFileOffset(from: fileOffset, in: machO)
        let layout: Pointee.Layout = try machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return .init(layout: layout, offset: offset)
    }
}

extension RelativePointer where Pointee: RelativePointerOptional, Pointee.Wrapped: LayoutWrapperWithOffset {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        let offset = try resolveFileOffset(from: fileOffset, in: machO)
        let layout: Pointee.Wrapped.Layout = try machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return .makeOptional(from: .init(layout: layout, offset: offset))
    }
}

extension RelativePointer where Pointee == ContextDescriptor {
    public func resolveContextDescriptor(from fileOffset: Int, in machO: MachOFile) throws -> ContextDescriptorWrapper? {
        guard isValid else { return nil }
        let offset = try resolveFileOffset(from: fileOffset, in: machO)
        return try machO.swift._readContextDescriptor(from: offset, in: machO)
    }
}

public struct TargetRelativeDirectPointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let relativeOffset: Offset
    public var isIndirect: Bool { false }
}

public struct TargetRelativeIndirectPointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let relativeOffset: Offset
    public var isIndirect: Bool { true }
}

public struct TargetRelativeIndirectablePointer<Pointee, Offset: FixedWidthInteger>: RelativePointer {
    public let relativeOffsetPlusIndirect: Offset
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }

    public func withIntPairPointer<Integer: FixedWidthInteger>(_ integer: Integer.Type = Integer.self) -> TargetRelativeIndirectablePointerIntPair<Pointee, Offset, Integer> {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }

    public func withValuePointer<Value: RawRepresentable>(_ integer: Value.Type = Value.self) -> TargetRelativeIndirectablePointerWithValue<Pointee, Offset, Value> where Value.RawValue: FixedWidthInteger {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }
}

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger, Integer: FixedWidthInteger>: RelativePointer {
    public let relativeOffsetPlusIndirectAndInt: Offset

    public var relativeOffset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast(relativeOffsetPlusIndirectAndInt & mask >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }
}

public struct TargetRelativeIndirectablePointerWithValue<Pointee, Offset: FixedWidthInteger, Value: RawRepresentable>: RelativePointer where Value.RawValue: FixedWidthInteger {
    public typealias Integer = Value.RawValue

    public let relativeOffsetPlusIndirectAndInt: Offset

    public var relativeOffset: Offset {
        (relativeOffsetPlusIndirectAndInt & ~mask) & ~1
    }

    public var mask: Offset {
        Offset(MemoryLayout<Offset>.alignment - 1) & ~1
    }

    public var intValue: Integer {
        numericCast(relativeOffsetPlusIndirectAndInt & mask >> 1)
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirectAndInt & 1 == 1
    }

    public var value: Value {
        return Value(rawValue: intValue)!
    }
}
