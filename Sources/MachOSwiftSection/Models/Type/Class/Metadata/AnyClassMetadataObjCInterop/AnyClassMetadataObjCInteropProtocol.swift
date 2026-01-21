import Foundation
import MachOKit
import MachOFoundation

public protocol AnyClassMetadataObjCInteropProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataObjCInteropLayout {}

extension AnyClassMetadataObjCInteropProtocol {
    public func asFinalClassMetadata<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ClassMetadataObjCInterop {
        try .resolve(from: offset, in: machO)
    }
    
    public func asFinalClassMetadata() throws -> ClassMetadataObjCInterop {
        try .resolve(from: asPointer)
    }
}

extension AnyClassMetadataObjCInteropProtocol {
    public func superclass<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve(in: machO)
    }
    
    public func superclass() throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve()
    }

    public var isPureObjC: Bool {
        !isTypeMetadata
    }

    public var isTypeMetadata: Bool {
        layout.data & 2 != 0
    }
}
