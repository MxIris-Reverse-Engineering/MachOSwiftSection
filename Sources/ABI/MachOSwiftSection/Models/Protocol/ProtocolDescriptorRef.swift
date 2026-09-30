import Foundation
import MachOKit
import MachOBase

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

// MARK: - ReadingContext Support

extension ProtocolDescriptorRef {
    public func objcProtocol(in context: some ReadingContext) throws -> ObjCProtocolPrefix {
        try Pointer<ObjCProtocolPrefix>(address: storage & ~Bits.isObjC).resolve(in: context)
    }

    public func swiftProtocol(in context: some ReadingContext) throws -> ProtocolDescriptor {
        try Pointer<ProtocolDescriptor>(address: storage).resolve(in: context)
    }

    public func name(in context: some ReadingContext) throws -> String {
        if isObjC {
            return try objcProtocol(in: context).name(in: context)
        } else {
            return try swiftProtocol(in: context).name(in: context)
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ProtocolDescriptorRef {
    @available(*, deprecated, message: "Pass a ReadingContext: objcProtocol(in: machO.context).")
    public func objcProtocol(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ObjCProtocolPrefix {
        try objcProtocol(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: swiftProtocol(in: machO.context).")
    public func swiftProtocol(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolDescriptor {
        try swiftProtocol(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: name(in: machO.context).")
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try name(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: objcProtocol(in: .inProcess).")
    public func objcProtocol() throws -> ObjCProtocolPrefix {
        try objcProtocol(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: swiftProtocol(in: .inProcess).")
    public func swiftProtocol() throws -> ProtocolDescriptor {
        try swiftProtocol(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: name(in: .inProcess).")
    public func name() throws -> String {
        try name(in: InProcessContext.shared)
    }
}
