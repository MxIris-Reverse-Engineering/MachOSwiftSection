import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ProtocolDescriptorRef {
    public let storage: StoredPointer

    private enum Bits {
        static let isObjC: UInt64 = 0x1
    }
    
    public var dispatchStrategy: ProtocolDispatchStrategy {
        if isObjC {
            return .objc
        } else {
            return .swift
        }
    }

    public func swiftProtocol<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> ProtocolDescriptor {
        try Pointer<ProtocolDescriptor>(address: storage).resolve(in: machO)
    }

    public func objcProtocol<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> ObjCProtocolPrefix {
        try Pointer<ObjCProtocolPrefix>(address: storage & ~Bits.isObjC).resolve(in: machO)
    }

    public var isObjC: Bool {
        storage & Bits.isObjC != 0
    }

    public func name<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> String {
        if isObjC {
            return try objcProtocol(in: machO).name(in: machO)
        } else {
            return try swiftProtocol(in: machO).name(in: machO)
        }
    }
    
    public static func forObjC(_ storage: StoredPointer) -> Self {
        .init(storage: storage | Bits.isObjC)
    }
    
    public static func forSwift(_ storage: StoredPointer) -> Self {
        .init(storage: storage)
    }
}


