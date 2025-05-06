import Foundation
import MachOKit

public typealias RelativeOffset = Int32
public typealias RelativeDirectPointer<Pointee> = TargetRelativeDirectPointer<Pointee, RelativeOffset>
public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<Any, RelativeOffset>
public typealias RelativeIndirectPointer<Pointee, IndirectType: RelativeIndirectType> = TargetRelativeIndirectPointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee
public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<Any, RelativeOffset, Pointer<Any>>
public typealias RelativeIndirectablePointer<Pointee, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee
public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<Any, RelativeOffset, Pointer<Any>>
public typealias RelativeIndirectablePointerIntPair<Pointee, Integer: FixedWidthInteger, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer, IndirectType> where Pointee == IndirectType.Pointee
public typealias RelativeIndirectableRawPointerIntPair<Integer: FixedWidthInteger> = TargetRelativeIndirectablePointerIntPair<Any, RelativeOffset, Integer, Pointer<Any>>

public protocol RelativePointerOptional: ExpressibleByNilLiteral {
    associatedtype Wrapped
    static func makeOptional(from wrappedValue: Wrapped) -> Self
}

extension Optional: RelativePointerOptional {
    public static func makeOptional(from wrappedValue: Wrapped) -> Self {
        return .some(wrappedValue)
    }
}

public protocol RelativePointer<Pointee>: RelativeReadable where Element == Pointee {
    associatedtype Pointee
    associatedtype Offset: FixedWidthInteger
    var relativeOffset: Offset { get }
    func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee
    func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T
    func resolveDirectFileOffset(from fileOffset: Int) -> Int
}

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointer {
//    func resolveDirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee
//    func resolveDirectAny<T>(from fileOffset: Int, in machO: MachOFile) throws -> T
}

//extension RelativeDirectPointerProtocol<String> {
//    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
//        return try resolveDirect(from: fileOffset, in: machO)
//    }
//
//    fileprivate func resolveDirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
//        return try read(offset: resolveDirectFileOffset(from: fileOffset), in: machO)
//    }
//}
    

extension RelativeDirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveDirect(from: fileOffset, in: machO)
    }

    fileprivate func resolveDirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try read(offset: resolveDirectFileOffset(from: fileOffset), in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveDirect(from: fileOffset, in: machO)
    }

    fileprivate func resolveDirect<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try read(offset: resolveDirectFileOffset(from: fileOffset), in: machO)
    }
}

public protocol RelativeIndirectPointerProtocol: RelativePointer {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Element == Pointee
//    func resolveIndirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee
//    func resolveIndirectType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType
//    func resolveIndirectAny<T>(from fileOffset: Int, in machO: MachOFile) throws -> T

    func resolveIndirectFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirect(from: fileOffset, in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirect(from: fileOffset, in: machO)
    }

    fileprivate func resolveIndirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirectType(from: fileOffset, in: machO).resolveAny(in: machO)
    }

    fileprivate func resolveIndirectType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType {
        return try read(offset: resolveDirectFileOffset(from: fileOffset), in: machO)
    }

    fileprivate func resolveIndirect<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirectType(from: fileOffset, in: machO).resolveAny(in: machO)
    }

    public func resolveIndirectFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machO).resolveOffset(in: machO)
    }
}

public protocol RelativeIndirectablePointerProtocol: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var isIndirect: Bool { get }

    func resolveIndirectableFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int
//    func resolveIndirectable(from fileOffset: Int, in machO: MachOFile) throws -> Pointee
//    func resolveIndirectableType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType?
//    func resolveIndirectableAny<T>(from fileOffset: Int, in machO: MachOFile) throws -> T
}

extension RelativeIndirectablePointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machO)
    }

    fileprivate func resolveIndirectable(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machO)
        } else {
            return try resolveDirect(from: fileOffset, in: machO)
        }
    }

    fileprivate func resolveIndirectableType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machO)
    }

    fileprivate func resolveIndirectableAny<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machO)
        } else {
            return try resolveDirect(from: fileOffset, in: machO)
        }
    }

    public func resolveIndirectableFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: fileOffset, in: machO) else { return resolveDirectFileOffset(from: fileOffset) }
        return indirectType.resolveOffset(in: machO)
    }
}

extension RelativePointer {
    //    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
    //        return try machO.fileHandle.read(offset: numericCast(resolveIndirectableFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
    //    }
    //
    //    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
    //        return try machO.fileHandle.read(offset: numericCast(resolveIndirectableFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
    //    }
    //
    //    public func resolveDirectFileOffset(from fileOffset: Int) -> Int {
    //        return Int(fileOffset) + Int(relativeOffset)
    //    }
    //
    //    public func resolveIndirectableFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
    //        let resolvedDirectFileOffset = resolveDirectFileOffset(from: fileOffset)
    //
    //        if isIndirect {
    //            let virtualAddress: UInt64 = try machO.fileHandle.read(offset: numericCast(resolvedDirectFileOffset + machO.headerStartOffset))
    //            let resolvedFileOffset: Int = machO.fileOffset(of: virtualAddress).cast()
    //            return resolvedFileOffset
    //        } else {
    //            return resolvedDirectFileOffset
    //        }
    //    }
    //
    //    public var isDirect: Bool {
    //        return !isIndirect
    //    }
    //

    public func resolveDirectFileOffset(from fileOffset: Int) -> Int {
        return Int(fileOffset) + Int(relativeOffset)
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
        let result: Pointee.Wrapped = try resolve(from: fileOffset, in: machO)
        return .makeOptional(from: result)
    }
}

// extension RelativePointer where Pointee == String? {
//    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee? {
//        guard isValid else { return nil }
//        return try machO.fileHandle.readString(offset: numericCast(resolveIndirectableFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset))
//    }
// }
//
// extension RelativePointer where Pointee == String {
//    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
//        return try machO.fileHandle.readString(offset: numericCast(resolveIndirectableFileOffset(from: fileOffset, in: machO) + machO.headerStartOffset)) ?? ""
//    }
// }
//
// extension RelativePointer where Pointee: LocatableLayoutWrapper {
//    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
//        let offset = try resolveIndirectableFileOffset(from: fileOffset, in: machO)
//        let layout: Pointee.Layout = try machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
//        return .init(layout: layout, offset: offset)
//    }
// }
//
// extension RelativePointer where Pointee: RelativePointerOptional, Pointee.Wrapped: LocatableLayoutWrapper {
//    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
//        guard isValid else { return nil }
//        let offset = try resolveIndirectableFileOffset(from: fileOffset, in: machO)
//        let layout: Pointee.Wrapped.Layout = try machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
//        return .makeOptional(from: .init(layout: layout, offset: offset))
//    }
// }

// extension RelativePointer where Pointee == ContextDescriptor {
//    public func resolveContextDescriptor(from fileOffset: Int, in machO: MachOFile) throws -> ContextDescriptorWrapper? {
//        guard isValid else { return nil }
//        let offset = try resolveIndirectableFileOffset(from: fileOffset, in: machO)
//        return try machO.swift._readContextDescriptor(from: offset, in: machO)
//    }
// }

public struct TargetRelativeDirectPointer<Pointee, Offset: FixedWidthInteger>: RelativeDirectPointerProtocol {
    public typealias Element = Pointee
    public let relativeOffset: Offset
    public var isIndirect: Bool { false }
}

public struct TargetRelativeIndirectPointer<Pointee, Offset: FixedWidthInteger, IndirectType: RelativeIndirectType>: RelativeIndirectPointerProtocol where Pointee == IndirectType.Pointee {
    public typealias Element = Pointee
    public let relativeOffset: Offset
    public var isIndirect: Bool { true }
}

public struct TargetRelativeIndirectablePointer<Pointee, Offset: FixedWidthInteger, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Pointee == IndirectType.Pointee {
    public typealias Element = Pointee
    public let relativeOffsetPlusIndirect: Offset
    public var relativeOffset: Offset {
        relativeOffsetPlusIndirect & ~1
    }

    public var isIndirect: Bool {
        return relativeOffsetPlusIndirect & 1 == 1
    }

    public func withIntPairPointer<Integer: FixedWidthInteger>(_ integer: Integer.Type = Integer.self) -> TargetRelativeIndirectablePointerIntPair<Pointee, Offset, Integer, IndirectType> {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }

    public func withValuePointer<Value: RawRepresentable>(_ integer: Value.Type = Value.self) -> TargetRelativeIndirectablePointerWithValue<Pointee, Offset, Value, IndirectType> where Value.RawValue: FixedWidthInteger {
        return .init(relativeOffsetPlusIndirectAndInt: relativeOffsetPlusIndirect)
    }
}

public protocol RelativeReadable<Element> {
    associatedtype Element
//    func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element
    func read<T>(offset fileOffset: Int, in machO: MachOFile) throws -> T
}

extension RelativeReadable<String> {
    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element {
        return machO.fileHandle.readString(offset: numericCast(fileOffset + machO.headerStartOffset)) ?? ""
    }
}

extension RelativeReadable {
//    @_disfavoredOverload
//    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element {
//        return try read(offset: fileOffset, in: machO)
//        return try machO.fileHandle.read(offset: numericCast(fileOffset + machO.headerStartOffset))
//    }

    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element where Element: LocatableLayoutWrapper {
        let layout: Element.Layout = try machO.fileHandle.read(offset: numericCast(fileOffset + machO.headerStartOffset))
        return .init(layout: layout, offset: fileOffset)
    }

    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element where Element == ContextDescriptorWrapper? {
        guard let contextDescriptor = try machO.swift._readContextDescriptor(from: fileOffset, in: machO) else { return nil }
        return contextDescriptor
    }

    public func read<T>(offset fileOffset: Int, in machO: MachOFile) throws -> T {
        return try machO.fileHandle.read(offset: numericCast(fileOffset + machO.headerStartOffset))
    }
}

// extension RelativeReadable where Element == String {
//    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element {
//        return machO.fileHandle.readString(offset: numericCast(fileOffset + machO.headerStartOffset)) ?? ""
//    }
// }

// extension RelativeReadable where Element: LocatableLayoutWrapper {
//    public func read(offset fileOffset: Int, in machO: MachOFile) throws -> Element {
//        let layout: Element.Layout = try machO.fileHandle.read(offset: numericCast(fileOffset + machO.headerStartOffset))
//        return .init(layout: layout, offset: fileOffset)
//    }
// }

public protocol RelativeIndirectType: RelativeReadable where Element == Pointee {
    associatedtype Pointee
    func resolve(in machO: MachOFile) throws -> Pointee
    func resolveAny<T>(in machO: MachOFile) throws -> T
    func resolveOffset(in machO: MachOFile) -> Int
}

public struct Pointer<Pointee>: RelativeIndirectType {
    public typealias Element = Pointee
    public let address: UInt64

    public func resolveOffset(in machO: MachOFile) -> Int {
        numericCast(machO.fileOffset(of: address))
    }

    public func resolveAny<T>(in machO: MachOFile) throws -> T {
        return try read(offset: resolveOffset(in: machO), in: machO)
    }

    public func resolve(in machO: MachOFile) throws -> Pointee {
        return try read(offset: resolveOffset(in: machO), in: machO)
    }
}

public struct TargetRelativeIndirectablePointerIntPair<Pointee, Offset: FixedWidthInteger, Integer: FixedWidthInteger, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Pointee == IndirectType.Pointee {
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

public struct TargetRelativeIndirectablePointerWithValue<Pointee, Offset: FixedWidthInteger, Value: RawRepresentable, IndirectType: RelativeIndirectType>: RelativeIndirectablePointerProtocol where Value.RawValue: FixedWidthInteger, Pointee == IndirectType.Pointee {
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
