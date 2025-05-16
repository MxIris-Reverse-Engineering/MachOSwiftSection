import MachOKit
import Foundation

public enum RelativeProtocolDescriptorPointer {
    case objcPointer(RelativeContextPointerIntPair<ObjCProtocolPrefix, Bool>)
    case swiftPointer(RelativeContextPointerIntPair<ProtocolDescriptor, Bool>)

    public var isObjC: Bool {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return relativeIndirectablePointerIntPair.value
        case .swiftPointer:
            return false
        }
    }

    public var rawPointer: RelativeIndirectableRawPointerIntPair<Bool> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeIndirectablePointerIntPair.relativeOffsetPlusIndirectAndInt)
        case .swiftPointer(let relativeContextPointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeContextPointerIntPair.relativeOffsetPlusIndirectAndInt)
        }
    }

    public func protocolDescriptorRef(from offset: Int, in machOFile: MachOFile) throws -> ProtocolDescriptorRef {
        let storedPointer = try rawPointer.resolveIndirectType(from: offset, in: machOFile).address
        if isObjC {
            return .forObjC(storedPointer)
        } else {
            return .forSwift(storedPointer)
        }
    }

    public func resolve(from offset: Int, in machOFile: MachOFile) throws -> ResolvableElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(from: offset, in: machOFile).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(from: offset, in: machOFile).map { .swift($0) }
        }
    }
}
