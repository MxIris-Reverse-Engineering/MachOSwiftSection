//
//  RelativeProtocolDescriptorPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//

import MachOKit
import Foundation

public enum RelativeProtocolDescriptorPointer {
    case objcPointer(RelativeIndirectablePointerIntPair<ObjCProtocolPrefix, Bool, Pointer<ObjCProtocolPrefix>>)
    case swiftPointer(RelativeContextPointerIntPair<ProtocolDescriptor, Bool>)

    public var isObjC: Bool {
        switch self {
        case let .objcPointer(relativeIndirectablePointerIntPair):
            return relativeIndirectablePointerIntPair.value
        case .swiftPointer:
            return false
        }
    }

    public var rawPointer: RelativeIndirectableRawPointerIntPair<Bool> {
        switch self {
        case let .objcPointer(relativeIndirectablePointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeIndirectablePointerIntPair.relativeOffsetPlusIndirectAndInt)
        case let .swiftPointer(relativeContextPointerIntPair):
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
}
