import Foundation
import MachOKit
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

    public var isObjC: Bool {
        storage & Bits.isObjC != 0
    }

    public static func forObjC(_ storage: StoredPointer) -> Self {
        .init(storage: storage | Bits.isObjC)
    }

    public static func forSwift(_ storage: StoredPointer) -> Self {
        .init(storage: storage)
    }
}

extension ProtocolDescriptorRef {
    public func objcProtocol<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ObjCProtocolPrefix {
        try Pointer<ObjCProtocolPrefix>(address: storage & ~Bits.isObjC).resolve(in: machO)
    }

    public func swiftProtocol<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolDescriptor {
        try Pointer<ProtocolDescriptor>(address: storage).resolve(in: machO)
    }

    public func name<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> String {
        if isObjC {
            return try objcProtocol(in: machO).name(in: machO)
        } else {
            return try swiftProtocol(in: machO).name(in: machO)
        }
    }
}

extension ProtocolDescriptorRef {
    public func objcProtocol() throws -> ObjCProtocolPrefix {
        try Pointer<ObjCProtocolPrefix>(address: storage & ~Bits.isObjC).resolve()
    }

    public func swiftProtocol() throws -> ProtocolDescriptor {
        try Pointer<ProtocolDescriptor>(address: storage).resolve()
    }

    public func name() throws -> String {
        if isObjC {
            return try objcProtocol().name()
        } else {
            return try swiftProtocol().name()
        }
    }
}
