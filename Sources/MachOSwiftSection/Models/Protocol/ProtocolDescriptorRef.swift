import Foundation
import MachOKit
import MachOSwiftSectionMacro
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

    @MachOImageGenerator
    public func swiftProtocol(in machOFile: MachOFile) throws -> ProtocolDescriptor {
        try Pointer<ProtocolDescriptor>(address: storage).resolve(in: machOFile)
    }

    @MachOImageGenerator
    public func objcProtocol(in machOFile: MachOFile) throws -> ObjCProtocolPrefix {
        try Pointer<ObjCProtocolPrefix>(address: storage & ~Bits.isObjC).resolve(in: machOFile)
    }

    public var isObjC: Bool {
        storage & Bits.isObjC != 0
    }

    @MachOImageGenerator
    public func name(in machOFile: MachOFile) throws -> String {
        if isObjC {
            return try objcProtocol(in: machOFile).name(in: machOFile)
        } else {
            return try swiftProtocol(in: machOFile).name(in: machOFile)
        }
    }
    
    public static func forObjC(_ storage: StoredPointer) -> Self {
        .init(storage: storage | Bits.isObjC)
    }
    
    public static func forSwift(_ storage: StoredPointer) -> Self {
        .init(storage: storage)
    }
}


